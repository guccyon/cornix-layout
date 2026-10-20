# frozen_string_literal: true

module Cornix
  module Application
    module Editor
      class PlanEdits
        # 画面での変更 1 つ（protocol.md の Change）。path は JSON の道筋（文字列か整数）、value は文字列・整数・真偽値
        Change = Data.define(:file, :path, :value) do
          def initialize(file:, path:, value:) = super(file: file, path: path.dup.freeze, value: value)
        end
      end
    end
  end
end
