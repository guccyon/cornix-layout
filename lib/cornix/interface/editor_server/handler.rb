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
        REGISTRY = {} # サブクラスの定義（rpc / notification）で埋まる。読み書きは registry / fetch / unregister で

        class << self
          attr_reader :method_name

          def rpc(name) = register(name, notification: false)

          def notification(name) = register(name, notification: true)

          def notification? = @notification == true

          # { 'profile/open' => Handlers::ProfileOpen, ... }（写し）
          def registry = REGISTRY.dup.freeze

          # name を受け持つハンドラのクラス（なければ nil）
          def fetch(name) = REGISTRY[name]

          # 登録を外す（テストで仮のハンドラを足したあとの片付け用）
          def unregister(name) = REGISTRY.delete(name)

          private

          def register(name, notification:)
            existing = REGISTRY[name]
            raise ArgumentError, "#{name} のハンドラはもうあります: #{existing}" if existing && existing != self
            if @method_name && @method_name != name
              raise ArgumentError, "#{self} はもう #{@method_name} を受け持っています（1 クラスに 1 メソッド）"
            end

            @method_name = name
            @notification = notification
            REGISTRY[name] = self
          end
        end

        def call(_params, _context) = raise(NotImplementedError)

        private

        # params[name] を取り出す。型が違うとき、または optional: false で値がないときは InvalidParams（data: { field: }）。
        # field は入れ子の値の道筋（既定は name）。params には入れ子の Hash も渡せる
        #   param(params, 'dir', String) / param(params, 'limit', Integer, optional: true)
        #   param(change, 'address', Hash, field: "changes[#{i}].address")
        def param(params, name, *types, optional: false, field: name)
          value = params[name]
          return value if value.nil? && optional
          return value if !value.nil? && (types.empty? || types.any? { |t| value.is_a?(t) })

          reason = value.nil? ? 'がありません' : 'の形が違います'
          raise RpcError.new(ErrorCodes::INVALID_PARAMS, "params の #{field} #{reason}", { field: field })
        end
      end
    end
  end
end
