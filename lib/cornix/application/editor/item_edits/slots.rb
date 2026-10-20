# frozen_string_literal: true

module Cornix
  module Application
    module Editor
      class ItemEdits
        # 読んだプロファイルのキーを書く欄すべて（参照の場所を探すのに使う）。
        #
        #   Slots.new(reading).all   #=> [Slot(address: { file:, path: }, keycode:, text:)]
        #
        # 並びはレイヤー（キーは position_map の順、エンコーダは左右の push / ccw / cw）→ マクロの手順のキー →
        # タップダンスの動作 → コンボのトリガーと出力 → shortcuts.yaml の値。
        # text はファイルに書いてある表記（注記付きの形なら key の値。書いていなければ nil）。
        # preset: のマクロの手順は同梱の定義なので含めない
        class Slots
          Slot = Data.define(:address, :keycode, :text)

          def initialize(reading)
            @reading = reading
          end

          def all
            profile = @reading.profile
            entries = layer_entries(profile) + macro_entries(profile) + tap_dance_entries(profile) + combo_entries(profile)
            slots = entries.filter_map do |model_path, keycode|
              file, path = @reading.repository.address(model_path)
              next unless file

              Slot.new(address: { file: file, path: path }, keycode: keycode, text: @reading.document(file)&.scalar(path))
            end
            (slots + shortcut_slots(profile)).uniq(&:address)
          end

          private

          def layer_entries(profile)
            map = profile.position_map
            profile.layers.each_with_index.flat_map do |layer, i|
              keys = map.positions.filter_map do |pos|
                keycode = layer.key(pos)
                ["layers[#{i}].#{map.path(pos)}", keycode] if keycode
              end
              encoders = Domain::Layer::ENCODER_SIDES.flat_map do |side|
                layer.encoder(side).actions.map { |action, keycode| ["layers[#{i}].encoders.#{side}.#{action}", keycode] }
              end
              keys + encoders
            end
          end

          def macro_entries(profile)
            profile.macros.each_with_index.flat_map do |macro, i|
              next [] if macro.preset

              macro.steps.each_with_index.flat_map do |step, j|
                next [] unless step.respond_to?(:keys)

                step.keys.each_with_index.map { |keycode, k| ["macros[#{i}].steps[#{j}].keys[#{k}]", keycode] }
              end
            end
          end

          def tap_dance_entries(profile)
            profile.tap_dances.each_with_index.flat_map do |tap_dance, i|
              tap_dance.actions.map { |action, keycode| ["tap_dances[#{i}].#{action}", keycode] }
            end
          end

          def combo_entries(profile)
            profile.combos.each_with_index.flat_map do |combo, i|
              triggers = combo.trigger_keys.each_with_index.map { |keycode, k| ["combos[#{i}].trigger_keys[#{k}]", keycode] }
              triggers + [["combos[#{i}].output_key", combo.output_key]]
            end
          end

          def shortcut_slots(profile)
            file = @reading.shortcuts_file or return []
            doc = @reading.document(file)
            profile.shortcuts.entries.map do |name, keycode|
              path = ['shortcuts', name]
              Slot.new(address: { file: file, path: path }, keycode: keycode, text: doc&.scalar(path))
            end
          end
        end
      end
    end
  end
end
