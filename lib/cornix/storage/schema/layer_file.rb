# frozen_string_literal: true

require_relative 'hand_groups'

module Cornix
  module Storage
    module Schema
      # layers/{番号}_{名前}.yaml
      #
      #   name: Base
      #   description: ...                     # 省略可
      #   index: 0                             # レイヤー番号（省くか空にすると未使用。compile に含めない）
      #   mapping:
      #     left_hand:                         # right_hand も同じ形
      #       row0: { tab: Tab, Q: Q, ... }    # キーは position_map.yaml のシンボル。書かない・空の値はキーなし
      #       row1:
      #         caps: { key: LCtrl, note: 注記 }   # 注記付きの形（KeycodeField#read_assignment）
      #       row2: ... row3: ...
      #       thumb: { l_left: ..., l_mid: ..., l_right: ... }   # 旧名の thumb_keys でも読める（HandGroups）
      #     encoders:                          # 省略した操作は KC_NO。値は注記付きの形も書ける
      #       left: { push: Mute, ccw: VolumeDown, cw: VolumeUp }
      #       right: { push: ..., ccw: ..., cw: ... }
      module LayerFile
        KEYS = %w[name description index mapping].freeze
        HANDS = Domain::PositionMap::HANDS.keys.freeze
        GROUPS = HandGroups::GROUPS
        SIDES = %w[left right].freeze
        ACTIONS = Domain::EncoderBinding::ACTIONS.map(&:to_s).freeze

        module_function

        def read(data, ctx, keycodes, position_map)
          hash = ctx.mapping(data, '', required: %w[name index mapping], allowed: KEYS) or return nil
          name = ctx.name(hash['name'], 'name')
          description = ctx.description(hash['description'])
          index = ctx.bounded(hash['index'], 'index', Domain::LayerRef::RANGE, 'レイヤー番号')
          mapping = ctx.mapping(hash['mapping'], 'mapping', required: HANDS, allowed: HANDS + ['encoders'])
          assignments = mapping && read_hands(mapping, ctx, keycodes, position_map)
          encoders = mapping && read_encoders(mapping['encoders'], ctx, keycodes)
          return nil if [name, index, assignments, encoders].any?(&:nil?) || description == :invalid

          ctx.build('') do
            Domain::Layer.new(index: index, name: name, description: description, encoders: encoders,
                              keys: assignments.transform_values(&:keycode), notes: KeycodeField.notes(assignments))
          end
        end

        # 読んだ中身の mapping の下の Hash（手 => その下の Hash。形が違えば空）。エディタがファイルの書いているキーを見るのに使う
        def hands(data)
          mapping = data.is_a?(Hash) ? data['mapping'] : nil
          mapping.is_a?(Hash) ? mapping : {}
        end

        # 位置 => KeycodeField::Assignment。問題があれば nil
        def read_hands(mapping, ctx, keycodes, position_map)
          assignments = {}
          results = HANDS.flat_map do |hand|
            loc = "mapping.#{hand}"
            next [false] if HandGroups.conflict?(mapping[hand], ctx, loc)

            groups = ctx.mapping(HandGroups.normalize(mapping[hand]), loc, required: GROUPS, allowed: GROUPS)
            next [false] unless groups

            GROUPS.map do |group|
              key = HandGroups.written_key(mapping[hand], group)
              read_group(groups[group], ctx, keycodes, position_map, hand, group, assignments, key)
            end
          end
          results.all? ? assignments : nil
        end

        # 1 つのグループ（left_hand.row0 など）を読み、assignments に足す。問題があれば false。
        # key はファイルが書いているグループのキー（問題の場所に使う。旧名の thumb_keys のことがある）
        def read_group(raw, ctx, keycodes, position_map, hand, group, assignments, key = group)
          return true if raw.nil?

          loc = "mapping.#{hand}.#{key}"
          hash = ctx.mapping(raw, loc, key_label: 'キーの名前') or return false
          hash.map do |symbol, value|
            symbol = symbol.to_s if symbol.is_a?(Integer) # position_map と同じく数字だけの名前も使える
            next false unless symbol.is_a?(String)

            position = position_map.position(hand, group, symbol)
            next unknown_symbol(ctx, "#{loc}.#{symbol}", position_map.symbols(hand, group), "#{hand}.#{key}") unless position
            next true if value.nil?

            assignment = keycodes.read_assignment(value, ctx, "#{loc}.#{symbol}") or next false
            assignments[position] = assignment
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
          actions = ACTIONS.to_h do |a|
            [a.to_sym, keycodes.read_assignment(hash[a], ctx, "#{loc}.#{a}", default: Domain::Keycode::NO_KEY)]
          end
          return nil unless actions.values.all?

          ctx.build(loc) do
            Domain::EncoderBinding.new(**actions.transform_values(&:keycode), notes: KeycodeField.notes(actions))
          end
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
              position = position_map.position(hand, group, symbol)
              keycode = layer.key(position)
              h[symbol] = keycodes.write_assignment(keycode, layer.note(position)) if keycode
            end
            [group, row]
          end
        end

        def write_encoders(layer, keycodes)
          SIDES.to_h do |side|
            binding = layer.encoder(side.to_sym)
            [side, binding.actions.to_h { |a, kc| [a.to_s, keycodes.write_assignment(kc, binding.note(a))] }]
          end
        end
      end
    end
  end
end
