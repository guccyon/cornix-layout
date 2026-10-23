# frozen_string_literal: true

module Cornix
  module Application
    module Editor
      class PlanEdits
        # 画面での変更 1 つ（protocol.md の Change と 12.3）。path は JSON の道筋（文字列か整数）。
        #
        #   op: :set（value を書く）| :remove（項目・要素を消す）| :insert（並びの index の前に value を足す）|
        #       :move（並びの from の要素を to へ動かす）
        #   field: :key（割り当て）| :note（注記。:set と :remove だけ）
        #   value: :set は文字列・整数・真偽値、:insert は文字列か MacroStepValue の Hash（文字列のキー）
        Change = Data.define(:file, :path, :value, :op, :field, :index, :from, :to) do
          def initialize(file:, path:, value: nil, op: :set, field: :key, index: nil, from: nil, to: nil)
            super(file: file, path: path.dup.freeze, value: value, op: op, field: field, index: index, from: from, to: to)
          end

          def note? = field == :note

          # protocol.md の 12.3 の Change の形（profile/planItemEdit の result の changes。set は op を省く）
          def to_protocol
            h = { address: { file: file, path: path } }
            h[:op] = op.to_s unless op == :set
            h[:field] = 'note' if note?
            case op
            when :set then h[:value] = value
            when :insert then h.merge!(index: index, value: value)
            when :move then h.merge!(from: from, to: to)
            end
            h
          end
        end
      end
    end
  end
end
