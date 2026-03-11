# frozen_string_literal: true

require_relative 'metadata'
require_relative 'settings'
require_relative 'layer'
require_relative 'layer_collection'
require_relative 'macro'
require_relative 'macro_collection'
require_relative 'tap_dance'
require_relative 'tap_dance_collection'
require_relative 'combo'
require_relative 'combo_collection'

module Cornix
  module Models
    # VialConfig - Root Aggregate
    # 全てのモデルを集約し、QMK形式とYAML形式の双方向変換を提供
    class VialConfig
      attr_reader :metadata, :settings, :layers, :macros, :tap_dances, :combos, :extra_keys

      def initialize(metadata:, settings:, layers:, macros:, tap_dances:, combos:, extra_keys: {})
        @metadata = metadata          # Metadata
        @settings = settings          # Settings
        @layers = layers              # LayerCollection
        @macros = macros              # MacroCollection
        @tap_dances = tap_dances      # TapDanceCollection
        @combos = combos              # ComboCollection
        @extra_keys = extra_keys      # Hash（余分なキーを保持）
      end

      # QMK Hash → VialConfig
      def self.from_qmk(qmk_hash, position_map, keycode_converter, reference_converter: nil)
        # Metadata
        metadata = Metadata.from_qmk(qmk_hash)

        # Settings
        settings = Settings.from_qmk(qmk_hash['settings'] || {})

        # Layers (10レイヤー固定)
        layout_array = qmk_hash['layout'] || []
        encoder_array = qmk_hash['encoder_layout'] || []
        layers = []
        layout_array.each_with_index do |layout_2d, index|
          encoder_2d = encoder_array[index] || []
          layer = Layer.from_qmk(index, layout_2d, encoder_2d, position_map, keycode_converter, reference_converter: reference_converter)
          layers << layer
        end
        layer_collection = LayerCollection.new(layers)

        # Macros (32マクロ固定)
        macro_array = qmk_hash['macro'] || []
        macros = []
        macro_array.each_with_index do |qmk_macro, index|
          next if qmk_macro.nil? || qmk_macro.empty?
          macro = Macro.from_qmk(index, qmk_macro)
          # 空のマクロはスキップ
          next if macro.empty?
          macros << macro
        end
        macro_collection = MacroCollection.new(macros)

        # TapDance (32タップダンス固定)
        tap_dance_array = qmk_hash['tap_dance'] || []
        tap_dances = []
        tap_dance_array.each_with_index do |qmk_tap_dance, index|
          next if qmk_tap_dance.nil? || qmk_tap_dance.empty? || qmk_tap_dance.all? { |v| v == -1 }
          tap_dance = TapDance.from_qmk(index, qmk_tap_dance)
          # 空のタップダンス（全てKC_NO）はスキップ
          next if tap_dance.empty?
          tap_dances << tap_dance
        end
        tap_dance_collection = TapDanceCollection.new(tap_dances)

        # Combos (32コンボ固定)
        combo_array = qmk_hash['combo'] || []
        combos = []
        combo_array.each_with_index do |qmk_combo, index|
          next if qmk_combo.nil? || qmk_combo.empty? || qmk_combo.all? { |v| v == -1 }
          combo = Combo.from_qmk(index, qmk_combo)
          # 空のコンボ（全てKC_NO）はスキップ
          next if combo.empty?
          combos << combo
        end
        combo_collection = ComboCollection.new(combos)

        # 余分なキーを保存（既知のキー以外）
        known_keys = ['version', 'uid', 'vendor_product_id', 'product_id', 'matrix', 'vial_protocol', 'via_protocol',
                      'settings', 'layout', 'encoder_layout', 'macro', 'tap_dance', 'combo']
        extra_keys = qmk_hash.reject { |k, _v| known_keys.include?(k) }

        new(
          metadata: metadata,
          settings: settings,
          layers: layer_collection,
          macros: macro_collection,
          tap_dances: tap_dance_collection,
          combos: combo_collection,
          extra_keys: extra_keys
        )
      end

      # VialConfig → QMK Hash
      def to_qmk(position_map:, keycode_converter:, reference_converter:)
        qmk_hash = @metadata.to_qmk
        qmk_hash['settings'] = @settings.to_qmk
        qmk_hash['layout'] = @layers.to_qmk_layout_array(position_map: position_map, keycode_converter: keycode_converter, reference_converter: reference_converter)
        qmk_hash['encoder_layout'] = @layers.to_qmk_encoder_array(position_map: position_map, keycode_converter: keycode_converter, reference_converter: reference_converter)
        qmk_hash['macro'] = @macros.to_qmk_array
        qmk_hash['tap_dance'] = @tap_dances.to_qmk_array
        qmk_hash['combo'] = @combos.to_qmk_array

        # 余分なキーをマージ
        qmk_hash.merge(@extra_keys)
      end

      # 複数の YAML Hash → VialConfig
      def self.from_yaml_hashes(metadata_hash:, settings_hash:, layers_hashes:, macros_hashes:, tap_dances_hashes:, combos_hashes:, position_map:, keycode_converter:, reference_converter:)
        # Extra keys をmetadataから抽出
        extra_keys = metadata_hash['extra_keys'] || {}

        # Metadata
        metadata = Metadata.from_yaml_hash(metadata_hash)

        # Settings
        settings = Settings.from_yaml_hash(settings_hash)

        # Layers
        layers = layers_hashes.map do |layer_hash|
          Layer.from_yaml_hash(layer_hash, position_map)
        end
        layer_collection = LayerCollection.new(layers)

        # Macros
        macros = macros_hashes.map do |macro_hash|
          Macro.from_yaml_hash(macro_hash)
        end
        macro_collection = MacroCollection.new(macros)

        # TapDance
        tap_dances = tap_dances_hashes.map do |tap_dance_hash|
          TapDance.from_yaml_hash(tap_dance_hash)
        end
        tap_dance_collection = TapDanceCollection.new(tap_dances)

        # Combos
        combos = combos_hashes.map do |combo_hash|
          Combo.from_yaml_hash(combo_hash)
        end
        combo_collection = ComboCollection.new(combos)

        new(
          metadata: metadata,
          settings: settings,
          layers: layer_collection,
          macros: macro_collection,
          tap_dances: tap_dance_collection,
          combos: combo_collection,
          extra_keys: extra_keys
        )
      end

      # VialConfig → 複数の YAML Hash
      def to_yaml_hashes(keycode_converter:, reference_converter:)
        metadata_hash = @metadata.to_yaml_hash
        # extra_keysをmetadataに追加
        metadata_hash['extra_keys'] = @extra_keys unless @extra_keys.empty?

        {
          metadata: metadata_hash,
          settings: @settings.to_yaml_hash,
          layers: @layers.map { |layer| layer.to_yaml_hash(keycode_converter: keycode_converter, reference_converter: reference_converter) },
          macros: @macros.map { |macro| macro.to_yaml_hash },
          tap_dances: @tap_dances.map { |td| td.to_yaml_hash },
          combos: @combos.map { |combo| combo.to_yaml_hash }
        }
      end
    end
  end
end
