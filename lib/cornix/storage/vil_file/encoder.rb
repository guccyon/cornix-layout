# frozen_string_literal: true

require_relative '../vil_file'

module Cornix
  module Storage
    class VilFile
      # Image::DeviceImage → .vil の Hash（JSON.pretty_generate する前の形）。
      #
      # キーの順は旧 Models::VialConfig#to_qmk と同じ:
      # HEADER_KEYS のうち meta にあるもの → settings → layout → encoder_layout → macro → tap_dance → combo
      # → meta の残り（元の順）
      class Encoder
        def initialize(vial)
          @vial = vial
        end

        def encode(image)
          meta = image.meta.to_h { |key, value| [key.to_s, value] }
          result = HEADER_KEYS.select { |key| meta.key?(key) }.to_h { |key| [key, meta[key]] }
          result['settings'] = image.settings.sort_by { |qsid, _| qsid.to_i }.to_h { |qsid, value| [qsid.to_s, value] }
          result['layout'] = image.layers.map { |rows| rows.map { |cols| cols.map { |code| code.nil? ? NO_KEY : key(code) } } }
          result['encoder_layout'] = image.encoders.map { |encs| encs.map { |enc| [key(enc.ccw), key(enc.cw)] } }
          result['macro'] = image.macros.map { |actions| actions.map { |action| macro_action(action) } }
          result['tap_dance'] = image.tap_dances.map { |td| tap_dance(td) }
          result['combo'] = image.combos.map { |combo| [*combo.keys, combo.output].map { |code| key(code) } }
          meta.each { |key, value| result[key] = value unless result.key?(key) }
          result
        end

        private

        def key(code) = @vial.format_code(code)

        def macro_action(action)
          case action.kind
          when :tap, :down, :up then [action.kind.to_s, *action.keys.map { |code| key(code) }]
          else [action.kind.to_s, action.value]
          end
        end

        def tap_dance(record)
          [record.on_tap, record.on_hold, record.on_double_tap, record.on_tap_hold].map { |code| key(code) } +
            [record.tapping_term]
        end
      end
    end
  end
end
