# frozen_string_literal: true

require_relative 'invalid_change'

module Cornix
  module Application
    module Editor
      class PlanEdits
        # Change の値を宛先の型に合わせて確かめ、ファイルに書く値にする（protocol.md の 5.6 の「値の型」と 12.3）。
        # 合わなければ InvalidChange（field: "changes[i].value"）。
        #
        #   values = Values.new(reading)
        #   values.for(target, change, i)   #=> 書く値（:remove と :move では nil）
        #
        # - キー（:key）・文字列（:string）・注記は文字列、:integer は整数
        # - QMK 設定は data/qmk_settings.yaml の型（真偽値の設定は true / false か 0 / 1。ファイルが 0 / 1 で書いていれば 0 / 1）
        # - マクロの手順（:step）は MacroStepValue（{ action: tap|down|up, keys: string[] } / { action: delay, duration: 整数 } /
        #   { action: text, content: 文字列 }）で、ほかの項目は書けない。ファイルには action を先にした Hash で書く
        class Values
          ZERO_OR_ONE = /\A[01]\z/
          STEP_FIELDS = { 'tap' => 'keys', 'down' => 'keys', 'up' => 'keys', 'delay' => 'duration', 'text' => 'content' }.freeze

          def initialize(reading)
            @reading = reading
          end

          def for(target, change, index)
            field = "changes[#{index}].value"
            case change.op
            when :set then change.note? ? string(change.value, field, '注記') : set_value(target, change.value, field)
            when :insert then target.type == :step ? step(change.value, field) : string(change.value, field, 'キーの値')
            end
          end

          private

          def set_value(target, value, field)
            case target.type
            when :setting then setting(target, value, field)
            when :integer
              return value if value.is_a?(Integer)

              raise InvalidChange.new(field, "#{target.path.last} の値は整数にしてください")
            when :string then string(value, field, "#{target.path.last} の値")
            else string(value, field, 'キーの値')
            end
          end

          def string(value, field, what)
            return value if value.is_a?(String)

            raise InvalidChange.new(field, what == 'キーの値' ? 'キーの値は表記の文字列にしてください' : "#{what}は文字列にしてください")
          end

          def setting(target, value, field)
            definition = target.setting
            if definition.boolean?
              flag = { true => true, false => false, 1 => true, 0 => false }.fetch(value) do
                raise InvalidChange.new(field, "#{definition.name} の値は true か false にしてください")
              end
              return written_as_integer?(target) ? (flag ? 1 : 0) : flag
            end
            return value if value.is_a?(Integer)

            raise InvalidChange.new(field, "#{definition.name} の値は整数にしてください")
          end

          # 真偽値の設定を、ファイルが 0 / 1 で書いているか
          def written_as_integer?(target)
            node_text = @reading.document(target.file)&.scalar(target.path)
            !node_text.nil? && ZERO_OR_ONE.match?(node_text)
          end

          def step(value, field)
            invalid = -> { raise InvalidChange.new(field, "マクロの手順は #{step_forms} のどれかにしてください") }
            invalid.call unless value.is_a?(Hash)
            action = value['action']
            name = STEP_FIELDS[action] or invalid.call
            invalid.call unless value.keys.sort == ['action', name].sort

            content = value[name]
            ok = case name
                 when 'keys' then content.is_a?(Array) && content.all?(String)
                 when 'duration' then content.is_a?(Integer)
                 else content.is_a?(String)
                 end
            invalid.call unless ok
            { 'action' => action, name => content }
          end

          def step_forms = '{ action: tap|down|up, keys: [表記] }・{ action: delay, duration: 整数 }・{ action: text, content: 文字列 }'
        end
      end
    end
  end
end
