# frozen_string_literal: true

require 'json'
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
      # initialize の前と shutdown の後に来た通知は捨てる。exit の通知で run を終える。
      # 終了コードは shutdown を受けていれば 0、なければ 1（exit なしで入力が終わったときも同じ）。
      #
      # 通知とリクエストの別はハンドラ（rpc / notification）に合わせる。rpc のメソッドを通知で送られたら実行せずにログに書き、
      # notification のメソッドを id 付きで送られたら -32600 を返す
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

            write_response(handle(message))
          end
          exit_code
        rescue Framing::HeaderError => e
          log("入力の枠が読めないので終わります: #{e.message}")
          exit_code
        end

        # 1 メッセージ（JSON を読んだもの）を処理して、応答（Hash）を返す。通知なら nil
        def handle(message)
          return error_response(nil, invalid_request('JSON-RPC 2.0 のメッセージ（オブジェクト）ではありません')) unless message.is_a?(Hash)

          request = message.key?('id')
          id = message['id']
          return error_response(nil, invalid_request('id は文字列か整数にしてください')) if request && !valid_id?(id)
          return client_response(message) if request && !message.key?('method')

          name = message['method']
          unless message['jsonrpc'] == '2.0' && name.is_a?(String)
            return request ? error_response(id, invalid_request('JSON-RPC 2.0 のメッセージではありません')) : nil
          end

          dispatch(name, message['params'], id, request)
        end

        private

        def read_message
          Framing.read(@input) || :eof
        rescue Framing::ParseError => e
          log("JSON として読めないメッセージ: #{e.message}")
          write_response(error_response(nil, RpcError.new(ErrorCodes::PARSE_ERROR, 'JSON として読めません')))
          :skip
        rescue Framing::InvalidMessage => e
          write_response(handle(e.value))
          :skip
        end

        def dispatch(name, params, id, request)
          gate = lifecycle_gate(name, request)
          return (gate == :drop ? nil : error_response(id, gate)) if gate

          handler = Handler.fetch(name)
          return kind_mismatch(name, id, request) if handler && handler.notification? == request

          result = invoke(handler, name, params, request)
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

        # rpc のメソッドを通知で送られた（実行せずに捨てる）か、notification のメソッドを id 付きで送られた（-32600）
        def kind_mismatch(name, id, request)
          return error_response(id, invalid_request("#{name} は通知で送るメソッドです（id を付けない）")) if request

          log("#{name} はリクエストで送るメソッドです（id がないので実行しません）")
          nil
        end

        def invoke(handler, name, params, request)
          if handler.nil?
            # $/ で始まる知らない通知は何もしない。リクエストは知らないメソッドとして断る（LSP と同じ）
            return nil if name.start_with?('$/') && !request

            raise RpcError.new(ErrorCodes::METHOD_NOT_FOUND, "知らないメソッドです: #{name}")
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
          log_exception("#{name} の処理で例外", e)
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

        # 拡張からの応答（result か error を持つ）は、v0.1 ではサーバーからリクエストを送らないので読み捨てる。
        # どちらも持たず method もないものは JSON-RPC の形でないので -32600
        def client_response(message)
          unless message.key?('result') || message.key?('error')
            return error_response(message['id'], invalid_request('method も result / error もありません'))
          end

          log("知らない応答を読み捨てます: id=#{message['id'].inspect}")
          nil
        end

        def invalid_request(message) = RpcError.new(ErrorCodes::INVALID_REQUEST, message)

        def error_response(id, error) = { jsonrpc: '2.0', id: id, error: error.to_h }

        def log_failure(name, error)
          log("通知 #{name} を処理できませんでした: #{error.message}")
          nil
        end

        # 応答を書く。結果を JSON にできなければ（正しくない UTF-8、NaN など）、その id で -32603 を返す
        def write_response(response)
          return if response.nil?

          Framing.write(@output, response)
        rescue JSON::JSONError, EncodingError => e
          log_exception('応答を JSON にできません', e)
          Framing.write(@output, error_response(response[:id], RpcError.new(ErrorCodes::INTERNAL_ERROR,
                                                                            "応答を JSON にできません（#{e.class}）")))
        end

        def send_notification(method, params)
          Framing.write(@output, { jsonrpc: '2.0', method: method, params: params })
        rescue JSON::JSONError, EncodingError => e
          log_exception("通知 #{method} を JSON にできません", e)
        end

        def log_exception(label, error)
          log("#{label}: #{error.class}: #{error.message}\n#{Array(error.backtrace).first(10).join("\n")}")
        end

        def log(message)
          @error.puts("[cornix serve] #{message}")
          @error.flush if @error.respond_to?(:flush)
        end
      end
    end
  end
end
