# frozen_string_literal: true

module Cornix
  module Application
    module Editor
      class PlanEdits
        # baseVersions が今のファイルの版と違う（protocol.md の 9 の VersionConflict）。files は食い違ったファイルの今の版
        # （ファイルがなければ nil）
        class VersionConflict < Cornix::Error
          attr_reader :files

          def initialize(files)
            @files = files.dup.freeze
            super("ファイルが変更を作ったときの版と違います（外で変わりました）: #{files.keys.join(', ')}")
          end
        end

        # Change の形や宛先が正しくない（指せない Address、値の型が違う、変更のあるファイルの baseVersions がない）。
        # field は params の中の場所（"changes[0].address"）
        class InvalidChange < Cornix::Error
          attr_reader :field

          def initialize(field, message)
            @field = field
            super(message)
          end
        end

        # 値の部分だけでは書き換えられない（protocol.md の 9 の EditNotLocal）。
        # address は { file:, path: }、reason は約束の文字列（"multiline" | "anchor" | "flowInsert"）
        class NotLocal < Cornix::Error
          REASONS = { multiline: 'multiline', anchor: 'anchor', flow_insert: 'flowInsert' }.freeze

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
