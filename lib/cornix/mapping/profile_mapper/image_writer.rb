# frozen_string_literal: true

module Cornix
  module Mapping
    class ProfileMapper
      # Profile → DeviceImage（旧 VialConfig#to_qmk と同じ配置・パディング）。
      #
      #   layers      capabilities.layers 枚。レイヤーは index の位置に置き、定義のないレイヤーはすべて nil。
      #               割り当てのない位置とキーのない位置は nil、エンコーダのプッシュはマトリクスの
      #               PositionMap#encoder_push_matrix の位置
      #   encoders    [layer][左, 右] の EncoderRecord（定義のないレイヤーは ccw / cw とも nil）
      #   macros      capabilities.macros 個。未使用は []
      #   tap_dances  capabilities.tap_dances 個。未使用は KC_NO × 4 と DEFAULT_TAPPING_TERM
      #   combos      capabilities.combos 個。トリガーは combo_keys 個まで 0（KC_NO）で埋める。未使用はすべて 0
      #   settings    QmkSettings の値（QSID の昇順）
      #   meta        version / uid / vial_protocol / via_protocol（nil でも書く）、vendor_product_id /
      #               product_id / matrix（あれば）、metadata の extra_keys（旧 Metadata#to_qmk + extra_keys）
      class ImageWriter
        ENCODER_SIDES = %i[left right].freeze
        ALWAYS_META = %w[version uid vial_protocol via_protocol].freeze
        OPTIONAL_META = %w[vendor_product_id product_id matrix].freeze

        def initialize(profile, codec:, capabilities:)
          @profile = profile
          @codec = codec
          @caps = capabilities
        end

        def call
          layers = slots(profile.layers, caps.layers, 'レイヤー')
          Image::DeviceImage.new(
            layers: layers.map { |layer| layer ? layer_grid(layer) : empty_grid },
            encoders: layers.map { |layer| layer ? encoder_records(layer) : empty_encoders },
            macros: slots(profile.macros, caps.macros, 'マクロ').map { |m| m ? macro_actions(m) : [] },
            tap_dances: slots(profile.tap_dances, caps.tap_dances, 'タップダンス').map { |td| tap_dance_record(td) },
            combos: slots(profile.combos, caps.combos, 'コンボ').map { |c| combo_record(c) },
            settings: profile.settings.to_h,
            meta: meta
          )
        end

        private

        attr_reader :profile, :codec, :caps

        def position_map = profile.position_map

        # 枠の数の配列に index の位置で並べる（重複していれば先のもの = Profile#layer などと同じ）
        def slots(items, limit, what)
          items.each_with_object(Array.new(limit)) do |item, result|
            raise InvalidValue, "#{what}の番号は 0〜#{limit - 1} です: #{item.index}" if item.index >= limit

            result[item.index] ||= item
          end
        end

        def encode(keycode) = codec.encode(keycode)

        # --- レイヤー ---

        def empty_grid = Array.new(Domain::PositionMap::MATRIX_ROWS) { Array.new(Domain::PositionMap::MATRIX_COLS) }

        def empty_encoders = ENCODER_SIDES.map { Image::EncoderRecord.new(ccw: nil, cw: nil) }

        def layer_grid(layer)
          grid = empty_grid
          layer.keys.each do |position, keycode|
            row, col = position_map.matrix(position)
            grid[row][col] = encode(keycode)
          end
          ENCODER_SIDES.each do |side|
            row, col = position_map.encoder_push_matrix(side)
            grid[row][col] = encode(layer.encoder(side).push)
          end
          grid
        end

        def encoder_records(layer)
          ENCODER_SIDES.map do |side|
            binding = layer.encoder(side)
            Image::EncoderRecord.new(ccw: encode(binding.ccw), cw: encode(binding.cw))
          end
        end

        # --- マクロ / タップダンス / コンボ ---

        def macro_actions(macro)
          macro.steps.map do |step|
            case step
            when Domain::MacroStep::Delay then Image::MacroAction.new(kind: :delay, value: step.ms)
            when Domain::MacroStep::Text then Image::MacroAction.new(kind: :text, value: step.content)
            else Image::MacroAction.new(kind: step.kind, keys: step.keys.map { |k| encode(k) })
            end
          end
        end

        def tap_dance_record(tap_dance)
          if tap_dance.nil?
            return Image::TapDanceRecord.new(on_tap: 0, on_hold: 0, on_double_tap: 0, on_tap_hold: 0,
                                             tapping_term: DEFAULT_TAPPING_TERM)
          end

          Image::TapDanceRecord.new(**tap_dance.actions.transform_values { |k| encode(k) },
                                    tapping_term: tap_dance.tapping_term)
        end

        def combo_record(combo)
          return Image::ComboRecord.new(keys: Array.new(caps.combo_keys, 0), output: 0) if combo.nil?

          keys = combo.trigger_keys
          if keys.size > caps.combo_keys
            raise InvalidValue, "#{combo} のトリガーは #{caps.combo_keys} 個までです: #{keys.size} 個"
          end

          Image::ComboRecord.new(keys: keys.map { |k| encode(k) } + Array.new(caps.combo_keys - keys.size, 0),
                                 output: encode(combo.output_key))
        end

        # --- メタデータ ---

        def meta
          metadata = profile.metadata
          always = ALWAYS_META.to_h { |f| [f, metadata.public_send(f)] }
          optional = OPTIONAL_META.to_h { |f| [f, metadata.public_send(f)] }.compact
          extra_keys = metadata.extra_keys
          raise InvalidValue, "metadata の extra_keys は Hash です: #{extra_keys.inspect}" unless extra_keys.is_a?(Hash)

          always.merge(optional).merge(extra_keys)
        end
      end
    end
  end
end
