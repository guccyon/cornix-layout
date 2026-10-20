# frozen_string_literal: true

module Cornix
  module Application
    module Editor
      class PlanEdits
        # 値の部分だけでは書き換えられない（protocol.md の 9 の EditNotLocal）。
        # address は { file:, path: }、reason は約束の文字列（"multiline" | "anchor" | "flowInsert"）。
        # 前に別の内容がある行（「- action: tap」の行など）の書き換えは、約束の reason を足さずに "flowInsert" にする
        class NotLocal < Cornix::Error
          REASONS = { multiline: 'multiline', anchor: 'anchor', flow_insert: 'flowInsert', shared_line: 'flowInsert' }.freeze

          attr_reader :address, :reason

          def initialize(address:, reason:, message:)
            @address = address
            @reason = REASONS.fetch(reason)
            super("#{message}。テキストで直してください")
          end
        end
      end
    end
  end
end
