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
      end
    end
  end
end
