# frozen_string_literal: true

module Cornix
  module Storage
    module Schema
      # layers/{番号}_{名前}.yaml
      #
      #   name: Base
      #   description: ...                     # 省略可
      #   index: 0                             # レイヤー番号
      #   mapping:
      #     left_hand:                         # right_hand も同じ形
      #       row0: { tab: Tab, Q: Q, ... }    # キーは position_map.yaml のシンボル。書かない・空の値はキーなし
      #       row1: ... row2: ... row3: ...
      #       thumb_keys: { left: ..., middle: ..., right: ... }
      #     encoders:                          # 省略した操作は KC_NO
      #       left: { push: Mute, ccw: VolumeDown, cw: VolumeUp }
      #       right: { push: ..., ccw: ..., cw: ... }
      module LayerFile
        KEYS = %w[name description index mapping].freeze
        HANDS = Domain::PositionMap::HANDS.keys.freeze
        GROUPS = Domain::PositionMap::GROUPS.keys.freeze
        SIDES = %w[left right].freeze
        ACTIONS = Domain::EncoderBinding::ACTIONS.map(&:to_s).freeze

        module_function

        def read(data, ctx, keycodes, position_map)
          hash = ctx.mapping(data, '', required: %w[name index mapping], allowed: KEYS) or return nil
          name = ctx.name(hash['name'], 'name')
          description = ctx.description(hash['description'])
          index = ctx.bounded(hash['index'], 'index', Domain::LayerRef::RANGE, 'レイヤー番号')
          mapping = ctx.mapping(hash['mapping'], 'mapping', required: HANDS, allowed: HANDS + ['encoders'])
          keys = mapping && read_hands(mapping, ctx, keycodes, position_map)
          encoders = mapping && read_encoders(mapping['encoders'], ctx, keycodes)
          return nil if [name, index, keys, encoders].any?(&:nil?) || description == :invalid

          ctx.build('') do
            Domain::Layer.new(index: index, name: name, description: description, keys: keys, encoders: encoders)
          end
        end

        def read_hands(mapping, ctx, keycodes, position_map)
          keys = {}
          results = HANDS.flat_map do |hand|
            groups = ctx.mapping(mapping[hand], "mapping.#{hand}", required: GROUPS, allowed: GROUPS)
            next [false] unless groups

            GROUPS.map { |group| read_group(groups[group], ctx, keycodes, position_map, hand, group, keys) }
          end
          results.all? ? keys : nil
        end

        # 1 つのグループ（left_hand.row0 など）を読み、keys に足す。問題があれば false
        def read_group(raw, ctx, keycodes, position_map, hand, group, keys)
          return true if raw.nil?

          loc = "mapping.#{hand}.#{group}"
          hash = ctx.mapping(raw, loc, key_label: 'キーの名前') or return false
          hash.map do |symbol, value|
            symbol = symbol.to_s if symbol.is_a?(Integer) # position_map と同じく数字だけの名前も使える
            next false unless symbol.is_a?(String)

            position = position_map.position(hand, group, symbol)
            next unknown_symbol(ctx, "#{loc}.#{symbol}", position_map.symbols(hand, group), "#{hand}.#{group}") unless position
            next true if value.nil?

            keycode = keycodes.read(value, ctx, "#{loc}.#{symbol}") or next false
            keys[position] = keycode
            true
          end.all?
        end

        def unknown_symbol(ctx, loc, symbols, group_path)
          ctx.problem(loc, "position_map の #{group_path} にないキーです（使えるキー: #{symbols.join(', ')}）")
          false
        end

        def read_encoders(raw, ctx, keycodes)
          return SIDES.to_h { |side| [side.to_sym, empty_encoder] } if raw.nil?

          hash = ctx.mapping(raw, 'mapping.encoders', allowed: SIDES) or return nil
          bindings = SIDES.to_h { |side| [side.to_sym, read_encoder(hash[side], ctx, keycodes, "mapping.encoders.#{side}")] }
          bindings.values.all? ? bindings : nil
        end

        def read_encoder(raw, ctx, keycodes, loc)
          return empty_encoder if raw.nil?

          hash = ctx.mapping(raw, loc, allowed: ACTIONS) or return nil
          actions = ACTIONS.to_h { |a| [a.to_sym, keycodes.read_optional(hash[a], ctx, "#{loc}.#{a}")] }
          return nil unless actions.values.all?

          ctx.build(loc) { Domain::EncoderBinding.new(**actions) }
        end

        def empty_encoder
          no = Domain::Keycode::NO_KEY
          Domain::EncoderBinding.new(push: no, ccw: no, cw: no)
        end

        # 旧 YamlWriter と同じ形（name, description, index, mapping）。割り当てのない位置は書かない
        def write(layer, keycodes, position_map)
          {
            'name' => layer.name,
            'description' => layer.description || '',
            'index' => layer.index,
            'mapping' => HANDS.to_h { |hand| [hand, write_hand(layer, hand, keycodes, position_map)] }
                              .merge('encoders' => write_encoders(layer, keycodes))
          }
        end

        def write_hand(layer, hand, keycodes, position_map)
          GROUPS.to_h do |group|
            row = position_map.symbols(hand, group).each_with_object({}) do |symbol, h|
              keycode = layer.key(position_map.position(hand, group, symbol))
              h[symbol] = keycodes.write(keycode) if keycode
            end
            [group, row]
          end
        end

        def write_encoders(layer, keycodes)
          SIDES.to_h do |side|
            binding = layer.encoder(side.to_sym)
            [side, ACTIONS.to_h { |a| [a, keycodes.write(binding.public_send(a))] }]
          end
        end
      end
    end
  end
end
