# frozen_string_literal: true

require_relative '../vil_file'

module Cornix
  module Storage
    class VilFile
      # JSON.parse した .vil の Hash → Image::DeviceImage。
      # 問題は「場所: 内容」の文字列で集め、decode が [image, problems] を返す（problems が空でなければ image は nil）。
      class Decoder
        MACRO_KEY_ACTIONS = { 'tap' => :tap, 'down' => :down, 'up' => :up }.freeze

        def initialize(vial)
          @vial = vial
        end

        def decode(data)
          @problems = []
          unless data.is_a?(Hash)
            problem('（ルート）', "JSON のオブジェクトではありません（#{type_name(data)}）")
            return [nil, @problems]
          end

          image = Image::DeviceImage.new(
            settings: settings(data.fetch('settings', {})),
            layers: layers(data.fetch('layout', [])),
            encoders: encoders(data.fetch('encoder_layout', [])),
            macros: macros(data.fetch('macro', [])),
            tap_dances: tap_dances(data.fetch('tap_dance', [])),
            combos: combos(data.fetch('combo', [])),
            meta: data.reject { |key, _| SECTIONS.include?(key) }
          )
          @problems.empty? ? [image, []] : [nil, @problems]
        end

        private

        def settings(value)
          return {} unless hash_at('settings', value)

          value.each_with_object({}) do |(qsid, setting), result|
            at = "settings[#{qsid.inspect}]"
            next problem(at, '設定の番号は 0 以上の整数です') unless qsid.match?(/\A\d+\z/)
            next problem(at, "設定の値は整数です（#{setting.inspect}）") unless setting.is_a?(Integer)

            result[qsid.to_i] = setting
          end
        end

        def layers(value)
          each_at('layout', value) do |layer, l|
            each_at("layout[#{l}]", layer) do |row, r|
              each_at("layout[#{l}][#{r}]", row) do |cell, c|
                cell == NO_KEY ? nil : keycode("layout[#{l}][#{r}][#{c}]", cell)
              end
            end
          end
        end

        def encoders(value)
          each_at('encoder_layout', value) do |layer, l|
            each_at("encoder_layout[#{l}]", layer) do |pair, e|
              at = "encoder_layout[#{l}][#{e}]"
              next unless fixed_array(at, pair, 2, '[反時計回り, 時計回り]')

              Image::EncoderRecord.new(ccw: keycode("#{at}[0]", pair[0]), cw: keycode("#{at}[1]", pair[1]))
            end
          end
        end

        def macros(value)
          each_at('macro', value) do |actions, m|
            each_at("macro[#{m}]", actions) { |action, a| macro_action("macro[#{m}][#{a}]", action) }
          end
        end

        def macro_action(at, action)
          return problem(at, "マクロの動作は配列です（#{type_name(action)}）") unless action.is_a?(Array)

          kind, *args = action
          if (key_kind = MACRO_KEY_ACTIONS[kind])
            keys = args.each_with_index.map { |key, i| keycode("#{at}[#{i + 1}]", key) }
            Image::MacroAction.new(kind: key_kind, keys: keys)
          elsif kind == 'delay'
            macro_value(at, args, :delay, '["delay", ミリ秒]') { |v| v.is_a?(Integer) && v >= 0 }
          elsif kind == 'text'
            macro_value(at, args, :text, '["text", 文字列]') { |v| v.is_a?(String) }
          else
            problem("#{at}[0]", "マクロの動作が不明です: #{kind.inspect}（tap / down / up / delay / text）")
          end
        end

        def macro_value(at, args, kind, shape)
          return problem(at, "#{shape} の形ではありません") unless args.size == 1 && yield(args[0])

          Image::MacroAction.new(kind: kind, value: args[0])
        end

        def tap_dances(value)
          each_at('tap_dance', value) do |entry, i|
            at = "tap_dance[#{i}]"
            next unless fixed_array(at, entry, 5, '[on_tap, on_hold, on_double_tap, on_tap_hold, tapping_term]')

            tap, hold, double, tap_hold = entry.first(4).each_with_index.map { |key, k| keycode("#{at}[#{k}]", key) }
            term = entry[4]
            problem("#{at}[4]", "tapping_term は 0 以上の整数です（#{term.inspect}）") unless term.is_a?(Integer) && term >= 0
            Image::TapDanceRecord.new(on_tap: tap, on_hold: hold, on_double_tap: double, on_tap_hold: tap_hold,
                                      tapping_term: term)
          end
        end

        def combos(value)
          each_at('combo', value) do |entry, i|
            at = "combo[#{i}]"
            next unless fixed_array(at, entry, 5, '[キー1, キー2, キー3, キー4, 出力]')

            codes = entry.each_with_index.map { |key, k| keycode("#{at}[#{k}]", key) }
            Image::ComboRecord.new(keys: codes.first(4), output: codes[4])
          end
        end

        def keycode(at, value)
          unless value.is_a?(String) || value.is_a?(Integer)
            return problem(at, "キーコードは文字列です（#{type_name(value)}）")
          end

          @vial.parse_code(value)
        rescue UnknownKeycode => e
          problem(at, e.message)
        end

        # 配列なら各要素をブロックで変換した配列、配列でなければ問題を記録して []
        def each_at(at, value, &)
          return [] unless array_at(at, value)

          value.each_with_index.map(&)
        end

        def array_at(at, value)
          value.is_a?(Array) || problem(at, "配列ではありません（#{type_name(value)}）") && false
        end

        def hash_at(at, value)
          value.is_a?(Hash) || problem(at, "オブジェクトではありません（#{type_name(value)}）") && false
        end

        def fixed_array(at, value, size, shape)
          return true if value.is_a?(Array) && value.size == size

          problem(at, "#{shape} の #{size} 要素の配列ではありません（#{value.inspect}）")
          false
        end

        # 問題を記録して nil を返す
        def problem(at, message)
          @problems << "#{at}: #{message}"
          nil
        end

        def type_name(value)
          case value
          when nil then 'null'
          when Hash then 'オブジェクト'
          when Array then '配列'
          when String then '文字列'
          when Integer, Float then '数値'
          when true, false then '真偽値'
          else value.class.name
          end
        end
      end
    end
  end
end
