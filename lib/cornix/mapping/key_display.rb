# frozen_string_literal: true

module Cornix
  module Mapping
    # キーボード図に描くキーの種類（kind）と短い文字（display）。VS Code 拡張の KeyValue の kind と display を作る
    # （docs/vscode-extension/protocol.md の KeyKind と KeyDisplay）。
    #
    #   display = KeyDisplay.new(catalog:, notation:)
    #   display.kind(keycode)                                     #=> "basic" | "modified" | "layerTap" | ...
    #   display.display(keycode, references:, layer_names: {})   #=> { label:, tap:, hold: }
    #
    # 文字の決め方
    #   基本キー・特殊キー  別名の先頭（Space、VolumeUp）。別名がなければ keycodes.yaml の name から KC_ を除いたもの（STOP）
    #   修飾キー単体        記号（⌃ ⌥ ⇧ ⌘。右側は R⇧ のように R を付ける）
    #   Modified            別名があれば別名（!）、なければ修飾キーの記号を macOS の並び（⌃⌥⇧⌘）で前に付ける（⇧⌘P）
    #   ModTap / LayerTap   2 役のキー。label と tap はタップ側のキー、hold は修飾キーの記号（⇧）か L<番号>（L1）
    #   LayerAction         操作の名前とレイヤー（MO Symbols）。レイヤーの名前がなければ L<番号>（MO L1）
    #   LayerMod            レイヤーと修飾キー（L1 ⇧）。OneShotMod は OSM ⇧
    #   MacroCall / TapDanceCall  名前（Bracket Pair）。名前がなければ M0 / TD(4)
    #   NoKey / Transparent 空の文字 / ▽（Vial と同じ）
    #   Raw                 0xHHHH
    #
    # LayerTap の hold は図の小さな文字なので、名前があっても L<番号> にする（protocol.md の profile/open の例と同じ）。
    class KeyDisplay
      K = Domain::Keycode

      KINDS = {
        K::Basic => 'basic', K::Modified => 'modified', K::LayerAction => 'layerAction', K::LayerTap => 'layerTap',
        K::LayerMod => 'layerMod', K::ModTap => 'modTap', K::OneShotMod => 'oneShotMod', K::MacroCall => 'macro',
        K::TapDanceCall => 'tapDance', K::Quantum => 'quantum', K::NoKey => 'noKey', K::Transparent => 'transparent',
        K::Raw => 'raw'
      }.freeze

      # 修飾キーの記号（macOS のメニューと同じ並び ⌃⌥⇧⌘）
      MODIFIER_ORDER = %i[ctrl alt shift gui].freeze
      MODIFIER_SYMBOLS = { ctrl: '⌃', alt: '⌥', shift: '⇧', gui: '⌘' }.freeze
      RIGHT_PREFIX = 'R'

      # 修飾キー単体の基本キー（KC_LCTRL〜KC_RGUI）→ [左右, 修飾キー]
      MODIFIER_KEYS = {
        0xE0 => %i[left ctrl], 0xE1 => %i[left shift], 0xE2 => %i[left alt], 0xE3 => %i[left gui],
        0xE4 => %i[right ctrl], 0xE5 => %i[right shift], 0xE6 => %i[right alt], 0xE7 => %i[right gui]
      }.freeze

      LAYER_OPS = {
        to: 'TO', momentary: 'MO', default: 'DF', toggle: 'TG',
        one_shot: 'OSL', tap_toggle: 'TT', persistent_default: 'PDF'
      }.freeze

      NO_KEY_LABEL = ''
      TRANSPARENT_LABEL = '▽'
      QMK_PREFIX = 'KC_'

      def initialize(catalog: KeycodeCatalog.default, notation: KeycodeNotation.new(catalog: catalog))
        @catalog = catalog
        @notation = notation
        @codec = notation.codec
      end

      # Keycode → KeyKind の文字列
      def kind(keycode)
        KINDS.fetch(keycode.class) { raise ArgumentError, "キーコードではありません: #{keycode.inspect}" }
      end

      # Keycode → { label:, tap:, hold: }（tap / hold は 2 役のキーだけ。ほかは nil）
      def display(keycode, references: References::NONE, layer_names: {})
        case keycode
        when K::ModTap then dual(key_label(keycode.base), modifier_symbols(keycode.mods))
        when K::LayerTap then dual(key_label(keycode.base), "L#{keycode.layer.index}")
        else single(label(keycode, references, layer_names))
        end
      end

      # ModifierSet → 記号（⇧⌘。右側は R⇧⌘）
      def modifier_symbols(mods)
        symbols = MODIFIER_ORDER.select { |m| mods.include?(m) }.map { |m| MODIFIER_SYMBOLS.fetch(m) }.join
        mods.right? ? "#{RIGHT_PREFIX}#{symbols}" : symbols
      end

      private

      def single(label) = { label: label, tap: nil, hold: nil }

      def dual(tap, hold) = { label: tap, tap: tap, hold: hold }

      def label(keycode, references, layer_names)
        case keycode
        when K::NoKey then NO_KEY_LABEL
        when K::Transparent then TRANSPARENT_LABEL
        when K::Basic, K::Quantum then key_label(keycode)
        when K::Modified then modified_label(keycode)
        when K::LayerAction then "#{LAYER_OPS.fetch(keycode.op)} #{layer_label(keycode.layer.index, layer_names)}"
        when K::LayerMod then "#{layer_label(keycode.layer.index, layer_names)} #{modifier_symbols(keycode.mods)}"
        when K::OneShotMod then "OSM #{modifier_symbols(keycode.mods)}"
        when K::MacroCall then references.macro_name(keycode.index) || "M#{keycode.index}"
        when K::TapDanceCall then references.tap_dance_name(keycode.index) || "TD(#{keycode.index})"
        when K::Raw then hex(keycode.code)
        else raise ArgumentError, "キーコードではありません: #{keycode.inspect}"
        end
      end

      # 基本キー・特殊キーの文字（修飾キー単体は記号）
      def key_label(keycode)
        code = @codec.encode(keycode)
        side, mod = MODIFIER_KEYS[code]
        return "#{side == :right ? RIGHT_PREFIX : ''}#{MODIFIER_SYMBOLS.fetch(mod)}" if mod

        @catalog.preferred_alias(code) || @catalog.name(code)&.delete_prefix(QMK_PREFIX) || hex(code)
      end

      def modified_label(keycode)
        @catalog.preferred_alias(@codec.encode(keycode)) || "#{modifier_symbols(keycode.mods)}#{key_label(keycode.base)}"
      end

      def layer_label(index, layer_names) = layer_names[index] || "L#{index}"

      def hex(code) = ::Kernel.format('0x%04X', code)
    end
  end
end
