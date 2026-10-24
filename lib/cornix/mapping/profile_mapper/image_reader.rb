# frozen_string_literal: true

module Cornix
  module Mapping
    class ProfileMapper
      # DeviceImage → Profile（旧 VialConfig.from_qmk に当たる）。ImageWriter と逆の対応で、
      # to_image(to_profile(image)) が image に戻るように読む。
      #
      #   レイヤー      すべての位置とエンコーダが KC_NO（か nil）のレイヤーは定義なしとして読まない（compile が KC_NO で
      #                 埋めて戻す）。ただしレイヤー 0 と、レイヤー操作のキー（MO(n) / LT(n, kc) など）が指すレイヤーは読む。
      #                 KC_TRNS は割り当てとみなす。キーの位置で nil のものは割り当てなし。エンコーダの nil は KC_NO
      #   マクロ        動作が空の枠は読まない
      #   タップダンス  KC_NO × 4 で tapping_term が DEFAULT_TAPPING_TERM（または nil）の枠は読まない
      #   コンボ        トリガーと出力がすべて KC_NO の枠は読まない。トリガーは末尾の KC_NO だけを落とす
      #                 （トリガーがすべて KC_NO で出力だけある枠は、トリガーを [KC_NO] として持つ）
      #   メタデータ    META_FIELDS は Metadata の項目、それ以外の項目は extra_keys
      class ImageReader
        ENCODER_SIDES = %i[left right].freeze
        NO = Domain::Keycode::NO_KEY

        def initialize(image, position_map:, codec:, inheritance:)
          @image = image
          @position_map = position_map
          @codec = codec
          @inheritance = inheritance
        end

        def call
          profile = Domain::Profile.new(
            metadata: metadata,
            settings: Domain::QmkSettings.new(values: image.settings.to_h),
            position_map: position_map,
            layers: layers,
            macros: macros,
            tap_dances: tap_dances,
            combos: combos,
            shortcuts: inheritance.shortcuts
          )
          kept = [0, *profile.referenced_layer_indexes]
          profile.with(layers: profile.layers.reject { |layer| layer.blank? && !kept.include?(layer.index) })
        end

        private

        attr_reader :image, :position_map, :codec, :inheritance

        def decode(code) = code.nil? ? NO : codec.decode(code)

        def named(kind, index)
          { index: index, name: inheritance.name(kind, index), description: inheritance.description(kind, index) }
        end

        # --- レイヤー ---

        def layers
          image.layers.each_with_index.map do |grid, index|
            encoders = image.encoders[index] || []
            keys = layer_keys(grid)
            Domain::Layer.new(**named(:layer, index), keys: keys, encoders: layer_encoders(index, grid, encoders),
                                                      notes: inheritance.notes(:layer, index, keys))
          end
        end

        def layer_keys(grid)
          position_map.positions.each_with_object({}) do |position, keys|
            row, col = position_map.matrix(position)
            code = grid.dig(row, col)
            keys[position] = codec.decode(code) unless code.nil?
          end
        end

        def layer_encoders(index, grid, records)
          ENCODER_SIDES.each_with_index.to_h do |side, i|
            row, col = position_map.encoder_push_matrix(side)
            record = records[i]
            actions = { push: decode(grid.dig(row, col)), ccw: decode(record&.ccw), cw: decode(record&.cw) }
            [side, Domain::EncoderBinding.new(**actions, notes: inheritance.encoder_notes(index, side, actions))]
          end
        end

        # --- マクロ / タップダンス / コンボ ---

        def macros
          image.macros.each_with_index.filter_map do |actions, index|
            next if actions.nil? || actions.empty?

            Domain::Macro.new(**named(:macro, index), steps: actions.map { |a| macro_step(a) })
          end
        end

        def macro_step(action)
          case action.kind
          when :tap then Domain::MacroStep::Tap.new(keys: action.keys.map { |k| codec.decode(k) })
          when :down then Domain::MacroStep::Down.new(keys: action.keys.map { |k| codec.decode(k) })
          when :up then Domain::MacroStep::Up.new(keys: action.keys.map { |k| codec.decode(k) })
          when :delay then Domain::MacroStep::Delay.new(ms: action.value)
          when :text then Domain::MacroStep::Text.new(content: action.value)
          end
        end

        def tap_dances
          image.tap_dances.each_with_index.filter_map do |record, index|
            next if record.nil? || unused_tap_dance?(record)

            actions = Domain::TapDance::ACTIONS.to_h { |a| [a, decode(record.public_send(a))] }
            Domain::TapDance.new(**named(:tap_dance, index), **actions,
                                 tapping_term: record.tapping_term || DEFAULT_TAPPING_TERM,
                                 notes: inheritance.notes(:tap_dance, index, actions))
          end
        end

        def unused_tap_dance?(record)
          Domain::TapDance::ACTIONS.all? { |a| no_key?(record.public_send(a)) } &&
            [nil, DEFAULT_TAPPING_TERM].include?(record.tapping_term)
        end

        def combos
          image.combos.each_with_index.filter_map do |record, index|
            next if record.nil? || (record.keys.all? { |k| no_key?(k) } && no_key?(record.output))

            output = { output_key: decode(record.output) }
            Domain::Combo.new(**named(:combo, index), trigger_keys: combo_triggers(record.keys), **output,
                                                     notes: inheritance.notes(:combo, index, output))
          end
        end

        def combo_triggers(keys)
          codes = keys.dup
          codes.pop while codes.any? && no_key?(codes.last)
          codes.empty? ? [NO] : codes.map { |k| decode(k) }
        end

        def no_key?(code) = code.nil? || code.zero?

        # --- メタデータ ---

        def metadata
          meta = image.meta
          fields = META_FIELDS.to_h { |f| [f.to_sym, meta[f]] }
          fields[:version] ||= 1 # version は Metadata の必須項目。.vil の version は常に 1
          Domain::Metadata.new(keyboard: inheritance.keyboard, **fields, extra: metadata_extra(meta))
        end

        # previous の extra の順を保ち、extra_keys だけを image の値に置き換える（なければ末尾に足す）
        def metadata_extra(meta)
          extra_keys = meta.reject { |k, _| META_FIELDS.include?(k) }
          extra = inheritance.metadata_extra.reject { |k, _| k == 'extra_keys' && extra_keys.empty? }
          return extra if extra_keys.empty?

          extra.merge('extra_keys' => extra_keys)
        end
      end
    end
  end
end
