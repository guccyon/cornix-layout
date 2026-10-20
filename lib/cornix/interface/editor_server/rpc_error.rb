# frozen_string_literal: true

module Cornix
  module Interface
    module EditorServer
      # ハンドラが送出すると JSON-RPC のエラーの応答になる。message は利用者に見せてよい日本語、data は機械向けの中身
      #
      #   raise RpcError.new(ErrorCodes::INVALID_PARAMS, 'dir が指定されていません', { field: 'dir' })
      class RpcError < StandardError
        attr_reader :code, :data

        def initialize(code, message, data = nil)
          @code = code
          @data = data
          super(message)
        end

        # 応答の error の中身
        def to_h = { code: code, message: message, data: data }.compact
      end
    end
  end
end
