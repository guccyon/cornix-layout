# frozen_string_literal: true

require_relative 'error_codes'
require_relative 'rpc_error'

module Cornix
  module Interface
    module EditorServer
      # メソッド 1 つを受け持つハンドラの基底。サブクラスで rpc か notification を書くと Handler.registry に載る
      # （サーバーは registry で振り分けるので、メソッドを足すときは handlers/ にファイルを足すだけでよい）。
      #
      #   class Handlers::ProfileOpen < Handler
      #     rpc 'profile/open'                      # 通知なら notification 'workspace/didChangeFiles'
      #     def call(params, context)               # params は Hash（キーは文字列）、context は Context
      #       dir = param(params, 'dir', String)
      #       { profileId: context.workbench.open(dir).id }   # → result（JSON にできるもの。通知では捨てる）
      #     end
      #   end
      #
      # 失敗は RpcError を送出する。Application::Editor::ProfileNotFound は -32050、ほかの Cornix::Error は -32603 になる
      class Handler
        REGISTRY = {} # サブクラスの定義（rpc / notification）で埋まる

        class << self
          attr_reader :method_name

          def rpc(name) = register(name, notification: false)

          def notification(name) = register(name, notification: true)

          def notification? = @notification == true

          # { 'profile/open' => Handlers::ProfileOpen, ... }
          def registry = REGISTRY.dup.freeze

          private

          def register(name, notification:)
            existing = REGISTRY[name]
            raise ArgumentError, "#{name} のハンドラはもうあります: #{existing}" if existing && existing != self

            @method_name = name
            @notification = notification
            REGISTRY[name] = self
          end
        end

        def call(_params, _context) = raise(NotImplementedError)

        private

        # params[name] を取り出す。型が違う（なければ optional: false のとき）は InvalidParams（data: { field: name }）
        #   param(params, 'dir', String) / param(params, 'limit', Integer, optional: true)
        def param(params, name, *types, optional: false)
          value = params[name]
          return value if value.nil? && optional
          return value if !value.nil? && (types.empty? || types.any? { |t| value.is_a?(t) })

          reason = value.nil? ? 'がありません' : 'の形が違います'
          raise RpcError.new(ErrorCodes::INVALID_PARAMS, "params の #{name} #{reason}", { field: name })
        end
      end
    end
  end
end
