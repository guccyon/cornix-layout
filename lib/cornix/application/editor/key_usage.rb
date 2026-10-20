# frozen_string_literal: true

module Cornix
  module Application
    module Editor
      # プロファイルでキーコードを使っている回数（16bit 値 => 回数）。キー入力欄の候補でよく使うキーを上に出すために数える
      # （tasks-v0.3.md の決めたことの 4、protocol.md の 13.3）。
      #
      #   KeyUsage.count(profile, codec) #=> { 0x0004 => 3, 0x5101 => 1, ... }
      #
      # 数えるところ: 全レイヤーのキーとエンコーダ（押す・左・右）、マクロの手順のキー（tap / down / up）、
      # タップダンスの動作、コンボのトリガーと出すキー。KC_NO・KC_TRNS は数えない（空きと「下のレイヤーのまま」はよく使うキーではないため。
      # 数えると、空の入力で NoKey・Trans が上に来てしまう）。profile が nil（構造検証で読めない）なら空
      module KeyUsage
        module_function

        def count(profile, codec)
          return {} unless profile

          keycodes(profile).each_with_object(Hash.new(0)) do |keycode, counts|
            next if keycode.is_a?(Domain::Keycode::NoKey) || keycode.is_a?(Domain::Keycode::Transparent)

            counts[codec.encode(keycode)] += 1
          end
        end

        def keycodes(profile)
          layers = profile.layers.flat_map { |layer| layer.keys.values + layer.encoders.values.flat_map { |e| e.actions.values } }
          macros = profile.macros.flat_map do |macro|
            macro.steps.flat_map { |step| step.respond_to?(:keys) ? step.keys : [] }
          end
          tap_dances = profile.tap_dances.flat_map { |tap_dance| tap_dance.actions.values }
          combos = profile.combos.flat_map { |combo| combo.trigger_keys + [combo.output_key] }
          layers + macros + tap_dances + combos
        end
      end
    end
  end
end
