# frozen_string_literal: true

require 'set'
require_relative 'protocol'

module Cornix
  module Device
    # 接続中のキーボード 1 台との通信の単位。Protocol と、最初に読み出したキーボードの形
    # （キーボード定義、マトリクスの大きさ、キーのある位置、エンコーダ数、マクロ・TD・コンボの枠数、扱う設定）を持つ。
    #
    #   Device::Session.open { |session| Device::Reader.new(session).read }
    #   Device::Session.new(transport, definition: ...)   # テストでは FakeRmkDevice を transport に渡す
    class Session
      attr_reader :protocol, :catalog, :settings_catalog, :definition, :connection_info, :dims, :positions,
                  :macro_count, :macro_buffer_size, :entry_counts, :setting_ids

      # HidBridge を開いて Session を渡す（ブロックを抜けると閉じる）
      def self.open(**options)
        HidBridge.open { |bridge| yield new(bridge, connection_info: bridge.info, **options) }
      end

      # transport: #transfer(bytes) → 32 バイトの応答（HidBridge）
      # definition: キーボード定義（省略時はデバイスから読む。展開に compression_tool を使う）
      def initialize(transport, catalog: Mapping::KeycodeCatalog.default,
                     settings_catalog: Mapping::QmkSettingCatalog.default, connection_info: {}, definition: nil)
        @catalog = catalog
        @settings_catalog = settings_catalog
        @connection_info = connection_info
        widths = settings_catalog.all.to_h { |d| [d.qsid, d.width] }
        @protocol = Protocol.new(transport, dangerous_keycode: catalog.method(:dangerous?), setting_widths: widths)
        @definition = definition || protocol.definition
        load_layout_info
      end

      # キーボード定義でキーがある位置か（マトリクスの物理座標）
      def key_position?(row, col) = positions.include?([row, col])

      # 接続中のキーボードの情報（旧 Device::Keyboard#info と同じ項目）
      def info
        id = protocol.keyboard_id
        {
          connection: connection_info,
          name: definition['name'],
          via_protocol: protocol.via_protocol_version,
          vial_protocol: id[:vial_protocol],
          uid: id[:uid],
          firmware_version: protocol.firmware_version,
          matrix: { rows: dims[:rows], cols: dims[:cols] },
          layers: dims[:layers],
          encoders: dims[:encoders],
          macros: { count: macro_count, buffer_size: macro_buffer_size },
          tap_dance: entry_counts[:tap_dance],
          combo: entry_counts[:combo],
          key_override: entry_counts[:key_override],
          settings: setting_ids,
          lock: protocol.unlock_status
        }
      end

      private

      def load_layout_info
        matrix = definition.fetch('matrix')
        positions, encoder_count = parse_kle(definition.dig('layouts', 'keymap') || [])
        @positions = positions.freeze
        @dims = { layers: protocol.layer_count, rows: matrix['rows'], cols: matrix['cols'], encoders: encoder_count }.freeze
        @macro_count = protocol.macro_count
        @macro_buffer_size = protocol.macro_buffer_size
        @entry_counts = protocol.dynamic_entry_counts.freeze
        @setting_ids = (protocol.supported_settings & protocol.setting_widths.keys).freeze
      end

      # KLE 形式のラベルからキーの位置とエンコーダ数を取り出す（Vial と同じく 10 行目が "e" ならエンコーダ）
      def parse_kle(rows)
        positions = Set.new
        encoders = 0
        rows.flatten.grep(String).each do |label|
          lines = label.split("\n", -1)
          a, b = lines[0].to_s.split(',').map(&:to_i)
          next if a.nil? || b.nil?

          if lines[9] == 'e'
            encoders = [encoders, a + 1].max
          else
            positions << [a, b]
          end
        end
        [positions, encoders]
      end
    end
  end
end
