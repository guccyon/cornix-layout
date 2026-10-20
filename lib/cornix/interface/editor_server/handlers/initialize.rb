# frozen_string_literal: true

require_relative '../handler'

module Cornix
  module Interface
    module EditorServer
      module Handlers
        # initialize: 約束の版を確かめ、サーバーの情報とできることを返す（protocol.md の 4.）。
        # 版は major.minor。1.0 になるまでは major.minor 全体、1.0 からは major が一致しなければ -32051 で断る
        class Initialize < Handler
          rpc 'initialize'

          PROTOCOL_VERSION = '0.3'
          SUPPORTED = [PROTOCOL_VERSION].freeze
          VERSION_PATTERN = /\A(\d+)\.(\d+)\z/

          def call(params, _context)
            requested = param(params, 'protocolVersion', String)
            unless compatible?(requested)
              raise RpcError.new(ErrorCodes::PROTOCOL_VERSION_MISMATCH,
                                 "約束の版が合いません（拡張: #{requested}、サーバー: #{SUPPORTED.join(', ')}）",
                                 { supported: SUPPORTED })
            end

            {
              protocolVersion: PROTOCOL_VERSION,
              serverInfo: { name: 'cornix', version: Cornix::VERSION, implementation: 'ruby' },
              capabilities: { semanticValidation: true, keycodeCode: true }
            }
          end

          private

          def compatible?(requested)
            major, minor = VERSION_PATTERN.match(requested)&.captures&.map(&:to_i)
            return false if major.nil?

            SUPPORTED.any? do |version|
              ours_major, ours_minor = version.split('.').map(&:to_i)
              major == ours_major && (ours_major >= 1 || minor == ours_minor)
            end
          end
        end
      end
    end
  end
end
