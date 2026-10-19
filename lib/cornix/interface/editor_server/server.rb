# frozen_string_literal: true

require_relative 'error_codes'
require_relative 'rpc_error'
require_relative 'framing'
require_relative 'context'
require_relative 'handler'

module Cornix
  module Interface
    module EditorServer
      # VS Code 拡張と話すサーバー（cornix serve。protocol.md）。標準入出力に Content-Length の枠で JSON-RPC 2.0 を流す。
      # 標準出力は JSON-RPC 専用で、ログは標準エラー出力に書く。リクエストは届いた順に 1 つずつ処理する。
      #
      #   Server.new(workbench: Application::Editor::Workbench.new(root: dir)).run   #=> 終了コード
      #   server.handle({ 'jsonrpc' => '2.0', 'id' => 1, 'method' => 'profile/list' })   #=> 応答の Hash | nil（通知）
      #
      # ライフサイクル（LSP と同じ）: initialize の前のリクエストは -32002、shutdown の後のリクエストは -32600。
      # その間の通知は捨てる。exit の通知で run を終える。終了コードは shutdown を受けていれば 0、なければ 1
      # （exit なしで入力が終わったときも同じ）
      class Server
        def initialize(workbench:, input: $stdin, output: $stdout, error: $stderr)
          @workbench = workbench
          @input = input
          @output = output
          @error = error
          @state = :uninitialized
          @shutdown_seen = false
          @context = Context.new(workbench: workbench, notifier: method(:send_notification), logger: method(:log))
        end

        def run
          @input.binmode if @input.respond_to?(:binmode)
          @output.binmode if @output.respond_to?(:binmode)
          until @state == :exited
            message = read_message
            break if message == :eof
            next if message == :skip

            response = handle(message)
            Framing.write(@output, response) if response
          end
          exit_code
        rescue Framing::HeaderError => e
          log("入力の枠が読めないので終わります: #{e.message}")
          exit_code
        end

        # 1 メッセージ（JSON を読んだもの）を処理して、応答（Hash）を返す。通知なら nil
        def handle(message)
          return error_response(nil, invalid_request('JSON-RPC 2.0 のメッセージではありません')) unless message.is_a?(Hash)

          request = message.key?('id')
          id = message['id']
          return error_response(nil, invalid_request('id は文字列か数にしてください')) if request && !valid_id?(id)
          return client_response(message) if !message.key?('method') && request

          name = message['method']
          unless message['jsonrpc'] == '2.0' && name.is_a?(String)
            return request ? error_response(id, invalid_request('JSON-RPC 2.0 のメッセージではありません')) : nil
          end

          dispatch(name, message['params'], request ? id : nil, request)
        end

        private

        def read_message
          Framing.read(@input) || :eof
        rescue Framing::ParseError => e
          log("JSON として読めないメッセージ: #{e.message}")
          Framing.write(@output, error_response(nil, RpcError.new(ErrorCodes::PARSE_ERROR, 'JSON として読めません')))
          :skip
        end

        def dispatch(name, params, id, request)
          gate = lifecycle_gate(name, request)
          return (gate == :drop ? nil : error_response(id, gate)) if gate

          result = invoke(name, params)
          after(name)
          request ? { jsonrpc: '2.0', id: id, result: result } : nil
        rescue RpcError => e
          request ? error_response(id, e) : log_failure(name, e)
        end

        # ライフサイクルで止めるとき RpcError か :drop（通知を捨てる）、通すとき nil
        def lifecycle_gate(name, request)
          return nil if name == 'exit'

          error =
            case @state
            when :uninitialized
              RpcError.new(ErrorCodes::SERVER_NOT_INITIALIZED, 'initialize の前です') unless name == 'initialize'
            when :shutdown
              invalid_request('shutdown の後です')
            else
              invalid_request('initialize はもう受けています') if name == 'initialize'
            end
          return nil if error.nil?

          request ? error : :drop
        end

        def invoke(name, params)
          handler = Handler.registry[name]
          if handler.nil?
            raise RpcError.new(ErrorCodes::METHOD_NOT_FOUND, "知らないメソッドです: #{name}") unless name.start_with?('$/')

            return nil # $/ で始まる知らない通知・リクエストは何もしない（LSP と同じ）
          end
          raise RpcError.new(ErrorCodes::INVALID_PARAMS, 'params はオブジェクトにしてください') unless params.nil? || params.is_a?(Hash)

          handler.new.call(params || {}, @context)
        rescue RpcError
          raise
        rescue Application::Editor::ProfileNotFound => e
          data = e.dir ? { dir: e.dir } : { profileId: e.profile_id }
          raise RpcError.new(ErrorCodes::PROFILE_NOT_FOUND, e.message, data)
        rescue Cornix::Error => e
          raise RpcError.new(ErrorCodes::INTERNAL_ERROR, e.message)
        rescue StandardError => e
          log("#{name} の処理で例外: #{e.class}: #{e.message}\n#{Array(e.backtrace).first(10).join("\n")}")
          raise RpcError.new(ErrorCodes::INTERNAL_ERROR, "サーバーの内部エラーです（#{e.class}: #{e.message}）")
        end

        # メソッドが成功したあとの状態の移り変わり
        def after(name)
          case name
          when 'initialize' then @state = :running
          when 'shutdown'
            @state = :shutdown
            @shutdown_seen = true
          when 'exit' then @state = :exited
          end
        end

        def exit_code = @shutdown_seen ? 0 : 1

        def valid_id?(id) = id.nil? || id.is_a?(String) || id.is_a?(Integer)

        # 拡張からの応答（v0.1 ではサーバーからリクエストを送らないので、読み捨てる）
        def client_response(message)
          log("知らない応答を読み捨てます: id=#{message['id'].inspect}")
          nil
        end

        def invalid_request(message) = RpcError.new(ErrorCodes::INVALID_REQUEST, message)

        def error_response(id, error) = { jsonrpc: '2.0', id: id, error: error.to_h }

        def log_failure(name, error)
          log("通知 #{name} を処理できませんでした: #{error.message}")
          nil
        end

        def send_notification(method, params)
          Framing.write(@output, { jsonrpc: '2.0', method: method, params: params })
        end

        def log(message)
          @error.puts("[cornix serve] #{message}")
          @error.flush if @error.respond_to?(:flush)
        end
      end
    end
  end
end
