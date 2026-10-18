# frozen_string_literal: true

module Cornix
  module Device
    # キーボードの状態をすべて読み出して Image::DeviceImage にする（旧 Device::Keyboard#read_state + #snapshot）。
    #
    # - layers: キーボード定義でキーのない位置（.vil の -1）は nil
    # - macros: マクロバッファを Mapping::MacroCodec で解読したもの（マクロ数ぶん）
    # - settings: デバイスが対応し、Mapping::QmkSettingCatalog にある設定だけ
    # - meta: .vil のトップレベル項目（version, uid, vial_protocol, via_protocol, layout_options, alt_repeat_key, key_override）
    class Reader
      NUL = "\x00".b.freeze

      def initialize(session, macro_codec: Mapping::MacroCodec.new)
        @session = session
        @macro_codec = macro_codec
      end

      def read
        Image::DeviceImage.new(
          layers: read_layers, encoders: read_encoders, macros: read_macros,
          tap_dances: Array.new(session.entry_counts[:tap_dance]) { |i| tap_dance(i) },
          combos: Array.new(session.entry_counts[:combo]) { |i| combo(i) },
          settings: session.setting_ids.to_h { |id| [id, protocol.setting(id)] },
          meta: read_meta
        )
      end

      private

      attr_reader :session

      def protocol = session.protocol

      def dims = session.dims

      def read_layers
        flat = protocol.keymap_buffer(dims[:layers], dims[:rows], dims[:cols])
        per_layer = dims[:rows] * dims[:cols]
        Array.new(dims[:layers]) do |l|
          Array.new(dims[:rows]) do |r|
            Array.new(dims[:cols]) do |c|
              session.key_position?(r, c) ? flat[(l * per_layer) + (r * dims[:cols]) + c] : nil
            end
          end
        end
      end

      def read_encoders
        Array.new(dims[:layers]) do |l|
          Array.new(dims[:encoders]) do |e|
            ccw, cw = protocol.encoder(l, e)
            Image::EncoderRecord.new(ccw: ccw, cw: cw)
          end
        end
      end

      # 読んだバッファはマクロ数ぶんの NUL で区切り直してから解読する（途中で打ち切った読み出しの余りを捨てる）
      def read_macros
        count = session.macro_count
        buffer = protocol.macro_buffer(session.macro_buffer_size, count)
        parts = buffer.b.split(NUL, -1) + ([''.b] * count)
        @macro_codec.decode_all(parts.first(count).map { |p| p + NUL }.join.b, count)
      end

      def tap_dance(index)
        td = protocol.tap_dance(index)
        tap, hold, double, tap_hold = td[:keys]
        Image::TapDanceRecord.new(on_tap: tap, on_hold: hold, on_double_tap: double, on_tap_hold: tap_hold,
                                  tapping_term: td[:term])
      end

      def combo(index)
        cb = protocol.combo(index)
        Image::ComboRecord.new(keys: cb[:keys], output: cb[:output])
      end

      def read_meta
        id = protocol.keyboard_id
        {
          'version' => 1, 'uid' => id[:uid], 'vial_protocol' => id[:vial_protocol],
          'via_protocol' => protocol.via_protocol_version,
          'layout_options' => 0, 'alt_repeat_key' => [], 'key_override' => []
        }
      end
    end
  end
end
