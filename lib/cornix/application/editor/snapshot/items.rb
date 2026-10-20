# frozen_string_literal: true

module Cornix
  module Application
    module Editor
      class Snapshot
        # マクロ・タップダンス・コンボ・ショートカットの中身（protocol.md の 12.2 の macros / tapDances / combos / shortcuts）。
        #
        #   items = Items.new(reading:, values:, description:)   # values は KeyValues、description は Inspect::Description
        #   items.to_h   #=> { macros: [...], tapDances: [...], combos: [...], shortcuts: [...] }
        #
        # 並びは references と同じ（読み込みの順。マクロ・タップダンス・コンボはファイル名の番号の順、ショートカットはファイルの順）。
        # i 番目の項目のファイルは ConfigRepository#address（読み込みと同じく各ディレクトリのファイルを名前順に並べた i 番目）。
        #
        # キーを入れる欄（KeySlot）は { address:, value: KeyValue | nil }。value の text はファイルに書いてある表記
        # （YamlDocument#scalar。注記付きの形なら key の値）で、書いていなければ value は nil（タップダンスの動作）。
        # マクロの手順のキーは名前参照を読まない欄（KeyValues の macroKey）、ショートカットの値は shortcutValue として読む。
        #
        # 決まり（12.2）
        #   マクロの手順の keys   1 つの値（keys: KC_A）で書いていれば要素 1 つで、その Address は ["sequence", i, "keys"]
        #   タップダンスの動作    actions: の下に書いていれば ["actions", "on_tap"]、上の階層なら ["on_tap"]。
        #                         動作をどちらにも書いていなければ actions: の下（Schema::TapDanceFile.write と同じ形）
        #   tapping_term          書いていなければ value は nil（読み込みでは 250）
        #   description           書いていなければ nil（空の文字列も読み込みで nil になる）。descriptionAddress はいつも ["description"]
        class Items
          MACRO_KEY = KeyValues::MACRO_KEY
          SHORTCUT_VALUE = KeyValues::SHORTCUT_VALUE
          TAP_DANCE_ACTIONS = { tap: :on_tap, hold: :on_hold, doubleTap: :on_double_tap, tapHold: :on_tap_hold }.freeze

          def initialize(reading:, values:, description:)
            @reading = reading
            @profile = reading.profile
            @values = values
            @description = description
          end

          def to_h
            { macros: macros, tapDances: tap_dances, combos: combos, shortcuts: shortcuts }
          end

          def macros
            @profile.macros.each_with_index.map do |macro, i|
              file = file_of('macros', i)
              header(macro, file).merge(
                icon: @values.macro_icon(macro),
                preset: macro.preset,
                presetAddress: macro.preset ? address(file, ['preset']) : nil,
                summary: @description.step_lines(macro),
                steps: macro.preset ? [] : macro_steps(macro, file)
              )
            end
          end

          def tap_dances
            @profile.tap_dances.each_with_index.map do |tap_dance, i|
              file = file_of('tap_dances', i)
              data = data(file)
              header(tap_dance, file).merge(
                actions: tap_dance_actions(tap_dance, file, data),
                tappingTerm: { address: address(file, ['tapping_term']),
                               value: data['tapping_term'].nil? ? nil : tap_dance.tapping_term }
              )
            end
          end

          # reachable はトリガーのキーがすべてそろうレイヤーがあるか（protocol.md の 13.2。Domain::ComboReachability）
          def combos
            reachability = Domain::ComboReachability.new(@profile)
            @profile.combos.each_with_index.map do |combo, i|
              file = file_of('combos', i)
              doc = @reading.document(file)
              triggers = combo.trigger_keys.each_with_index.map { |kc, j| slot(file, doc, ['trigger_keys', j], kc) }
              header(combo, file).merge(
                triggersAddress: address(file, ['trigger_keys']),
                triggers: triggers,
                output: slot(file, doc, ['output_key'], combo.output_key, note: combo.output_note),
                reachable: reachability.reachable?(combo)
              )
            end
          end

          def shortcuts
            file = @reading.shortcuts_file
            doc = file && @reading.document(file)
            @profile.shortcuts.entries.map do |name, keycode|
              path = ['shortcuts', name]
              text = doc&.scalar(path) || @values.canonical(keycode, context: SHORTCUT_VALUE)
              { name: name, address: address(file, path),
                value: @values.build(keycode, text: text, context: SHORTCUT_VALUE) }
            end
          end

          private

          def header(item, file)
            { index: item.index, name: item.name, description: item.description, file: file,
              descriptionAddress: address(file, ['description']) }
          end

          def macro_steps(macro, file)
            doc = @reading.document(file)
            sequence = data(file)['sequence']
            macro.steps.each_with_index.map do |step, i|
              path = ['sequence', i]
              base = { address: address(file, path) }
              case step
              when Domain::MacroStep::Delay
                base.merge(action: 'delay', duration: { address: address(file, path + ['duration']), value: step.ms })
              when Domain::MacroStep::Text
                base.merge(action: 'text', content: { address: address(file, path + ['content']), value: step.content })
              else
                base.merge(action: step.kind.to_s, **step_keys(step, file, doc, path + ['keys'], sequence[i]))
              end
            end
          end

          def step_keys(step, file, doc, keys_path, raw)
            single = !(raw.is_a?(Hash) && raw['keys'].is_a?(Array))
            keys = step.keys.each_with_index.map do |keycode, j|
              slot(file, doc, single ? keys_path : keys_path + [j], keycode, context: MACRO_KEY)
            end
            { keysAddress: address(file, keys_path), keys: keys }
          end

          def tap_dance_actions(tap_dance, file, data)
            doc = @reading.document(file)
            top_level = TAP_DANCE_ACTIONS.values.any? { |action| data.key?(action.to_s) }
            prefix = !data.key?('actions') && top_level ? [] : ['actions']
            TAP_DANCE_ACTIONS.to_h do |name, action|
              path = prefix + [action.to_s]
              text = doc&.scalar(path)
              value = text && @values.build(tap_dance.public_send(action), text: text, note: tap_dance.note(action))
              [name, { address: address(file, path), value: value }]
            end
          end

          # 書いてある値の KeySlot（表記が読めない値（空など）は正規形で埋める）
          def slot(file, doc, path, keycode, note: nil, context: nil)
            text = doc&.scalar(path) || @values.canonical(keycode, context: context)
            { address: address(file, path), value: @values.build(keycode, text: text, note: note, context: context) }
          end

          def file_of(kind, position) = @reading.repository.address("#{kind}[#{position}]").first

          def data(file)
            data = @reading.data(file)
            data.is_a?(Hash) ? data : {}
          end

          def address(file, path) = { file: file, path: path }
        end
      end
    end
  end
end
