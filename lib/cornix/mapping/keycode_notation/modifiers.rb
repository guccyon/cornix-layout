# frozen_string_literal: true

require_relative '../keycode_notation'

module Cornix
  module Mapping
    class KeycodeNotation
      # 設定ファイルの表記で使う修飾キーの名前（修飾キー式・修飾関数・MOD_ 定数）。
      # どれも Domain::ModifierSet の 5bit 表現（bit0 ctrl, bit1 shift, bit2 alt, bit3 gui, bit4 右側）に対応させる。
      module Modifiers
        # 修飾キー式（"Cmd + Shift + A"）の修飾名 → [左右, 修飾キー]。L/R を付けなければ左
        EXPRESSION = {
          'Shift' => %i[left shift], 'LShift' => %i[left shift],
          'Ctrl' => %i[left ctrl], 'LCtrl' => %i[left ctrl], 'Control' => %i[left ctrl], 'LControl' => %i[left ctrl],
          'Alt' => %i[left alt], 'LAlt' => %i[left alt], 'Option' => %i[left alt], 'LOption' => %i[left alt],
          'Cmd' => %i[left gui], 'LCmd' => %i[left gui], 'Command' => %i[left gui], 'LCommand' => %i[left gui],
          'Win' => %i[left gui], 'LWin' => %i[left gui], 'Gui' => %i[left gui], 'LGui' => %i[left gui],
          'RShift' => %i[right shift],
          'RCtrl' => %i[right ctrl], 'RControl' => %i[right ctrl],
          'RAlt' => %i[right alt], 'ROption' => %i[right alt],
          'RCmd' => %i[right gui], 'RCommand' => %i[right gui], 'RWin' => %i[right gui], 'RGui' => %i[right gui]
        }.freeze

        # format が修飾キー式を書くときの名前と順序（"Ctrl + Option + Shift + Command + X"）
        EXPRESSION_ORDER = %i[ctrl alt shift gui].freeze
        EXPRESSION_FORMAT = {
          left: { ctrl: 'Ctrl', alt: 'Option', shift: 'Shift', gui: 'Command' }.freeze,
          right: { ctrl: 'RCtrl', alt: 'ROption', shift: 'RShift', gui: 'RCommand' }.freeze
        }.freeze

        # 修飾関数（LSFT(kc), SGUI(kc) など）の正規名 → ビット。ModTap は「正規名_T」で書く。
        # Vial に名前があるもの（C_S, SGUI, MEH, HYPR など）は Vial の名前を正規名にする。
        FUNCTIONS = {
          'LCTL' => 0x01, 'LSFT' => 0x02, 'C_S' => 0x03, 'LALT' => 0x04, 'LCA' => 0x05, 'LSA' => 0x06,
          'MEH' => 0x07, 'LGUI' => 0x08, 'LCG' => 0x09, 'SGUI' => 0x0A, 'LCSG' => 0x0B, 'LAG' => 0x0C,
          'LCAG' => 0x0D, 'LSAG' => 0x0E, 'HYPR' => 0x0F,
          'RCTL' => 0x11, 'RSFT' => 0x12, 'RCS' => 0x13, 'RALT' => 0x14, 'RCA' => 0x15, 'RSA' => 0x16,
          'RGUI' => 0x18, 'RCG' => 0x19, 'RSG' => 0x1A, 'RCSG' => 0x1B, 'RAG' => 0x1C, 'RCAG' => 0x1D,
          'RSAG' => 0x1E
        }.freeze

        # 修飾関数の別名（QMK / Vial が受け付ける名前）
        FUNCTION_ALIASES = {
          'C' => 'LCTL', 'S' => 'LSFT', 'A' => 'LALT', 'G' => 'LGUI',
          'LOPT' => 'LALT', 'LCMD' => 'LGUI', 'LWIN' => 'LGUI',
          'ALGR' => 'RALT', 'ROPT' => 'RALT', 'RCMD' => 'RGUI', 'RWIN' => 'RGUI',
          'LCS' => 'C_S', 'LSG' => 'SGUI', 'SCMD' => 'SGUI', 'SWIN' => 'SGUI', 'SAGR' => 'RSA'
        }.freeze

        # 修飾関数名（別名を含む）→ ビット
        FUNCTION_BITS = FUNCTIONS.merge(FUNCTION_ALIASES.transform_values { |name| FUNCTIONS.fetch(name) }).freeze

        # ModTap の関数名（LGUI_T など。別名を含む）→ ビット
        MOD_TAP_BITS = FUNCTION_BITS
                       .reject { |name, _| name.size == 1 }
                       .to_h { |name, bits| ["#{name}_T", bits] }
                       .merge(
                         'CTL_T' => 0x01, 'SFT_T' => 0x02, 'ALT_T' => 0x04, 'OPT_T' => 0x04,
                         'GUI_T' => 0x08, 'CMD_T' => 0x08, 'WIN_T' => 0x08, 'ALL_T' => 0x0F
                       ).freeze

        # LM / OSM / MT の引数に書く MOD_ 定数 → ビット
        CONSTANTS = {
          'MOD_LCTL' => 0x01, 'MOD_LSFT' => 0x02, 'MOD_LALT' => 0x04, 'MOD_LGUI' => 0x08,
          'MOD_RCTL' => 0x11, 'MOD_RSFT' => 0x12, 'MOD_RALT' => 0x14, 'MOD_RGUI' => 0x18,
          'MOD_MEH' => 0x07, 'MOD_HYPR' => 0x0F
        }.freeze

        # format が MOD_ 定数を書くときの名前（1 つずつ | でつなぐ）
        CONSTANT_FORMAT = {
          left: { ctrl: 'MOD_LCTL', shift: 'MOD_LSFT', alt: 'MOD_LALT', gui: 'MOD_LGUI' }.freeze,
          right: { ctrl: 'MOD_RCTL', shift: 'MOD_RSFT', alt: 'MOD_RALT', gui: 'MOD_RGUI' }.freeze
        }.freeze

        module_function

        # ModifierSet → 修飾キー式の修飾名の並び（"Ctrl + Shift"）
        def expression(set)
          names = EXPRESSION_FORMAT.fetch(set.side)
          EXPRESSION_ORDER.select { |m| set.include?(m) }.map { |m| names.fetch(m) }.join(' + ')
        end

        # ModifierSet → "MOD_LCTL|MOD_LSFT"
        def constants(set)
          names = CONSTANT_FORMAT.fetch(set.side)
          set.mods.map { |m| names.fetch(m) }.join('|')
        end

        # ModifierSet → ModTap の関数名（正規名がなければ nil）
        def mod_tap_name(set)
          name = FUNCTIONS.key(set.bits)
          name && "#{name}_T"
        end
      end
    end
  end
end
