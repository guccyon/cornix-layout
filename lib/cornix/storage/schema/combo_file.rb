# frozen_string_literal: true

module Cornix
  module Storage
    module Schema
      # combos/{番号 2 桁}_{名前}.yaml
      #
      #   name: Bracket Pair
      #   description: ...                # 省略可
      #   enabled: true                   # 省略可（読み飛ばす）
      #   index: 0                        # コンボ番号
      #   trigger_keys: [KC_K, KC_L]      # 同時に押すキー
      #   output_key: Macro('Bracket Pair')
      module ComboFile
        KEYS = %w[name description enabled index trigger_keys output_key].freeze

        module_function

        def read(data, ctx, keycodes)
          hash = ctx.mapping(data, '', required: %w[name index trigger_keys output_key], allowed: KEYS) or return nil
          name = ctx.name(hash['name'], 'name')
          description = ctx.description(hash['description'])
          index = ctx.bounded(hash['index'], 'index', Domain::Combo::INDEX_RANGE, 'コンボ番号')
          triggers = read_triggers(hash['trigger_keys'], ctx, keycodes)
          output = keycodes.read(hash['output_key'], ctx, 'output_key')
          return nil if [name, index, triggers, output].any?(&:nil?) || description == :invalid

          ctx.build('') do
            Domain::Combo.new(index: index, name: name, description: description, trigger_keys: triggers,
                              output_key: output)
          end
        end

        def read_triggers(raw, ctx, keycodes)
          list = ctx.list(raw, 'trigger_keys', 'キーコードのリスト') or return nil
          return ctx.problem('trigger_keys', 'trigger_keys が空です') if list.empty?

          keys = list.each_with_index.map { |v, i| keycodes.read(v, ctx, "trigger_keys[#{i}]") }
          keys.all? ? keys : nil
        end

        # 旧 YamlWriter と同じ形（index, name, description, trigger_keys, output_key）
        def write(combo, keycodes)
          {
            'index' => combo.index,
            'name' => combo.name,
            'description' => combo.description || '',
            'trigger_keys' => combo.trigger_keys.map { |k| keycodes.write(k) },
            'output_key' => keycodes.write(combo.output_key)
          }
        end
      end
    end
  end
end
