# frozen_string_literal: true

module Cornix
  module Application
    module Editor
      class PlanEdits
        # Change の形や宛先が正しくない（指せない Address、値の型が違う、変更のあるファイルの baseVersions がない）。
        # field は params の中の場所（"changes[0].address"）
        class InvalidChange < Cornix::Error
          attr_reader :field

          def initialize(field, message)
            @field = field
            super(message)
          end
        end
      end
    end
  end
end
