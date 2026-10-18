# frozen_string_literal: true

require_relative 'checks'

module Cornix
  module Domain
    # デバイスの上限。Profile#diagnostics と ProfileMapper（未使用の枠のパディング）が使う
    #
    #   layers       レイヤーの数（layout.vil の layout / encoder_layout の枚数）
    #   macros       マクロの枠の数（M0〜）
    #   tap_dances   タップダンスの枠の数（TD(0)〜）
    #   combos       コンボの枠の数
    #   combo_keys   コンボ 1 件のトリガーの最大数
    class Capabilities < Data.define(:layers, :macros, :tap_dances, :combos, :combo_keys)
      def initialize(layers:, macros:, tap_dances:, combos:, combo_keys:)
        super(
          layers: Checks.integer!(layers, 1..32, 'レイヤーの数'),
          macros: Checks.integer!(macros, 0..256, 'マクロの数'),
          tap_dances: Checks.integer!(tap_dances, 0..256, 'タップダンスの数'),
          combos: Checks.integer!(combos, 0..256, 'コンボの数'),
          combo_keys: Checks.integer!(combo_keys, 1..8, 'コンボのトリガーの数')
        )
      end
    end

    # Cornix（RMK 0.8 系の Vial 互換ファームウェア）。旧 LayerCollection / MacroCollection /
    # TapDanceCollection / ComboCollection の MAX_SIZE と Combo のトリガー数、layout.vil の枠の数
    Capabilities.const_set(:CORNIX, Capabilities.new(layers: 10, macros: 32, tap_dances: 32, combos: 32, combo_keys: 4))
  end
end
