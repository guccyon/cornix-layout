# frozen_string_literal: true

module Cornix
  module Device
    # Planning::Change が書き込むキーコードを検査する。
    #
    # - KeycodeCatalog#dangerous?（data/dangerous_keycodes.yaml。QK_BOOT など）に当たる値があれば PlanRejected（PlanError。何も書かない）
    # - RMK 0.8 の from_via_keycode が解釈できない値は警告（ファームウェアが KC_NO として保存しうる）
    class ChangePolicy
      # RMK 0.8 の from_via_keycode が解釈できる範囲（それ以外は KC_NO として保存される）
      RMK_SUPPORTED = [
        0x0000..0x52BF, 0x5700..0x57FF, 0x7700..0x771F, 0x7C50..0x7C52,
        0x7C16..0x7C16, 0x7C73..0x7C73, 0x7C77..0x7C79, 0x7E00..0x7E0F
      ].freeze

      def initialize(catalog: Mapping::KeycodeCatalog.default, describer: ChangeDescriber.new(catalog: catalog))
        @catalog = catalog
        @describer = describer
      end

      # => [String] 警告。拒否するキーコードがあれば PlanRejected（keycodes に拒否したキーコードの表記。重なりは除く）。
      # message は最初に見つかったものの場所とキーコード
      def check!(changes)
        rejected = changes.flat_map { |change| change.keycodes.select { |code| @catalog.dangerous?(code) }.map { |code| [change, code] } }
        unless rejected.empty?
          change, code = rejected.first
          raise PlanRejected.new("#{@describer.describe(change)}: #{@describer.keycode(code)} は安全のため書き込めません",
                                 keycodes: rejected.map { |_, c| @describer.keycode(c) }.uniq)
        end
        changes.flat_map do |change|
          change.keycodes.reject { |code| supported?(code) }.map do |code|
            "#{@describer.describe(change)}: #{@describer.keycode(code)} はファームウェアが未対応のため KC_NO になる可能性があります"
          end
        end
      end

      def supported?(code) = RMK_SUPPORTED.any? { |range| range.cover?(code) }
    end
  end
end
