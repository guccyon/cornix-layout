# frozen_string_literal: true

module Cornix
  module Mapping
    # 16bit のキーコード ⇄ Domain::Keycode の変換（Vial protocol 6 / QMK の keycode v6 の配置）。
    #
    # decode は例外を出さず、解釈できない値は Keycode::Raw にする。
    # encode は表せない値（カタログにない基本キーなど）に UnknownKeycode を送出する。
    # 引数付きのキーコードは表ではなく、ここの定数とビット演算で組み立てる。
    class KeycodeCodec
      K = Domain::Keycode

      MODS = (0x0100..0x1FFF)
      MOD_TAP = (0x2000..0x3FFF)
      LAYER_TAP = (0x4000..0x4FFF)
      LAYER_MOD = (0x5000..0x51FF)
      ONE_SHOT_MOD = (0x52A0..0x52BF)
      TAP_DANCE = (0x5700..0x57FF)
      MACRO = (0x7700..0x77FF)

      # レイヤー操作の基準値（基準値 + レイヤー番号 0〜31）
      LAYER_OPS = {
        to: 0x5200, momentary: 0x5220, default: 0x5240, toggle: 0x5260,
        one_shot: 0x5280, tap_toggle: 0x52C0, persistent_default: 0x52E0
      }.freeze
      LAYER_OP_SPAN = 0x20

      def initialize(catalog = KeycodeCatalog.default)
        @catalog = catalog
      end

      attr_reader :catalog

      # Integer → Keycode
      def decode(code)
        raise ArgumentError, "キーコードは 0〜0xFFFF の整数です: #{code.inspect}" unless code.is_a?(Integer) && code.between?(0, 0xFFFF)

        decode_known(code) || K::Raw.new(code: code)
      end

      # Keycode → Integer
      def encode(keycode)
        case keycode
        when K::NoKey then 0x0000
        when K::Transparent then 0x0001
        when K::Basic then basic!(keycode)
        when K::Modified then (keycode.mods.bits << 8) | basic!(keycode.base)
        when K::ModTap then MOD_TAP.begin | (keycode.mods.bits << 8) | basic!(keycode.base)
        when K::LayerTap then LAYER_TAP.begin | (keycode.layer.index << 8) | basic!(keycode.base)
        when K::LayerMod then LAYER_MOD.begin | (keycode.layer.index << 5) | keycode.mods.bits
        when K::LayerAction then LAYER_OPS.fetch(keycode.op) + keycode.layer.index
        when K::OneShotMod then ONE_SHOT_MOD.begin | keycode.mods.bits
        when K::TapDanceCall then TAP_DANCE.begin + keycode.index
        when K::MacroCall then MACRO.begin + keycode.index
        when K::Quantum then quantum!(keycode)
        when K::Raw then keycode.code
        else raise UnknownKeycode, "キーコードではありません: #{keycode.inspect}"
        end
      end

      private

      def decode_known(code)
        case code
        when 0x0000 then K::NO_KEY
        when 0x0001 then K::TRANSPARENT
        when 0x0002..0x00FF then basic(code)
        when MODS then with_mods_and_base(code) { |mods, base| K::Modified.new(mods: mods, base: base) }
        when MOD_TAP then with_mods_and_base(code) { |mods, base| K::ModTap.new(mods: mods, base: base) }
        when LAYER_TAP then (base = basic(code & 0xFF)) && K::LayerTap.new(layer: layer((code >> 8) & 0x0F), base: base)
        when LAYER_MOD then (m = mods(code & 0x1F)) && K::LayerMod.new(layer: layer((code >> 5) & 0x0F), mods: m)
        when ONE_SHOT_MOD then (m = mods(code & 0x1F)) && K::OneShotMod.new(mods: m)
        when TAP_DANCE then K::TapDanceCall.new(index: code - TAP_DANCE.begin)
        when MACRO then K::MacroCall.new(index: code - MACRO.begin)
        else layer_action(code) || (K::Quantum.new(code: code) if @catalog.quantum?(code))
        end
      end

      def layer_action(code)
        op, base = LAYER_OPS.find { |_, b| (b...(b + LAYER_OP_SPAN)).cover?(code) }
        op && K::LayerAction.new(op: op, layer: layer(code - base))
      end

      def with_mods_and_base(code)
        m = mods((code >> 8) & 0x1F)
        base = basic(code & 0xFF)
        m && base ? yield(m, base) : nil
      end

      def basic(code) = (K::Basic.new(code: code) if @catalog.basic?(code))

      def mods(bits) = (Domain::ModifierSet.from_bits(bits) if bits.anybits?(0x0F))

      def layer(index) = Domain::LayerRef.new(index: index)

      def basic!(basic)
        return basic.code if @catalog.basic?(basic.code)

        raise UnknownKeycode, format('カタログにない基本キーです: 0x%02X', basic.code)
      end

      def quantum!(quantum)
        return quantum.code if @catalog.quantum?(quantum.code)

        raise UnknownKeycode, format('カタログにない特殊キーです: 0x%04X', quantum.code)
      end
    end
  end
end
