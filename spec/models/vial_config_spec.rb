# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../lib/cornix/models/vial_config'
require_relative '../../lib/cornix/models/metadata'
require_relative '../../lib/cornix/models/settings'
require_relative '../../lib/cornix/models/layer'
require_relative '../../lib/cornix/models/layer_collection'
require_relative '../../lib/cornix/models/macro'
require_relative '../../lib/cornix/models/macro_collection'
require_relative '../../lib/cornix/models/tap_dance'
require_relative '../../lib/cornix/models/tap_dance_collection'
require_relative '../../lib/cornix/models/combo'
require_relative '../../lib/cornix/models/combo_collection'
require_relative '../../lib/cornix/position_map'
require_relative '../../lib/cornix/converters/keycode_converter'

RSpec.describe Cornix::Models::VialConfig do
  let(:position_map) do
    position_map_path = File.join(__dir__, '../../config/position_map.yaml')
    Cornix::PositionMap.new(position_map_path)
  end

  let(:keycode_converter) do
    aliases_path = File.join(__dir__, '../../lib/cornix/keycode_aliases.yaml')
    Cornix::Converters::KeycodeConverter.new(aliases_path)
  end

  let(:metadata) do
    Cornix::Models::Metadata.new(
      keyboard: 'test_keyboard',
      version: 1,
      uid: 'TEST123',
      vendor_product_id: '0x1234:0x5678',
      product_id: '0x5678',
      matrix: { 'rows' => 8, 'cols' => 7 },
      vial_protocol: 6,
      via_protocol: 12
    )
  end

  let(:settings) do
    Cornix::Models::Settings.new({})
  end

  let(:empty_layer) do
    Cornix::Models::Layer.new(
      name: 'Empty Layer',
      description: '',
      index: 0,
      left_hand: Cornix::Models::Layer::HandMapping.empty(:left),
      right_hand: Cornix::Models::Layer::HandMapping.empty(:right),
      encoders: Cornix::Models::Layer::EncoderMapping.new(left: {}, right: {})
    )
  end

  let(:layer_collection) do
    Cornix::Models::LayerCollection.new([empty_layer])
  end

  let(:macro) do
    Cornix::Models::Macro.new(
      index: 0,
      name: 'Test Macro',
      description: 'Test',
      sequence: [1, 2, 3]
    )
  end

  let(:macro_collection) do
    Cornix::Models::MacroCollection.new([macro])
  end

  let(:tap_dance) do
    Cornix::Models::TapDance.new(
      index: 0,
      name: 'Test TapDance',
      description: 'Test',
      on_tap: 4,
      on_hold: 5,
      on_double_tap: 6,
      on_tap_hold: 7,
      tapping_term: 200
    )
  end

  let(:tap_dance_collection) do
    Cornix::Models::TapDanceCollection.new([tap_dance])
  end

  let(:combo) do
    Cornix::Models::Combo.new(
      index: 0,
      name: 'Test Combo',
      description: 'Test',
      trigger_keys: [20, 26],
      output_key: 43
    )
  end

  let(:combo_collection) do
    Cornix::Models::ComboCollection.new([combo])
  end

  describe '#initialize' do
    it '全てのモデルを集約' do
      config = described_class.new(
        metadata: metadata,
        settings: settings,
        layers: layer_collection,
        macros: macro_collection,
        tap_dances: tap_dance_collection,
        combos: combo_collection
      )

      expect(config.metadata).to eq(metadata)
      expect(config.settings).to eq(settings)
      expect(config.layers).to eq(layer_collection)
      expect(config.macros).to eq(macro_collection)
      expect(config.tap_dances).to eq(tap_dance_collection)
      expect(config.combos).to eq(combo_collection)
    end
  end

  describe '.from_qmk' do
    let(:qmk_hash) do
      {
        'keyboard' => 'test_keyboard',
        'version' => 1,
        'uid' => 'TEST123',
        'vendor_product_id' => '0x1234:0x5678',
        'product_id' => '0x5678',
        'matrix' => { 'rows' => 8, 'cols' => 7 },
        'vial_protocol' => 6,
        'via_protocol' => 12,
        'layout' => [
          Array.new(8) { Array.new(7, -1) }
        ],
        'encoder_layout' => [
          Array.new(2) { Array.new(2, -1) }
        ],
        'macro' => [
          [1, 2, 3]
        ],
        'tap_dance' => [
          [4, 5, 6, 7, 200]
        ],
        'combo' => [
          [20, 26, -1, -1, 43]
        ],
        'settings' => {}
      }
    end

    it 'QMK HashからVialConfigを生成' do
      config = described_class.from_qmk(qmk_hash, position_map, keycode_converter)

      expect(config.metadata.keyboard).to eq('Cornix')  # 固定値
      expect(config.metadata.version).to eq(1)
      expect(config.settings).to be_a(Cornix::Models::Settings)
      expect(config.layers).to be_a(Cornix::Models::LayerCollection)
      expect(config.macros).to be_a(Cornix::Models::MacroCollection)
      expect(config.tap_dances).to be_a(Cornix::Models::TapDanceCollection)
      expect(config.combos).to be_a(Cornix::Models::ComboCollection)
    end

    it 'レイヤーコレクションを正しく生成' do
      config = described_class.from_qmk(qmk_hash, position_map, keycode_converter)

      expect(config.layers.size).to eq(1)
      expect(config.layers[0]).to be_a(Cornix::Models::Layer)
      expect(config.layers[0].index).to eq(0)
    end

    it 'マクロコレクションを正しく生成' do
      config = described_class.from_qmk(qmk_hash, position_map, keycode_converter)

      expect(config.macros.size).to eq(1)
      expect(config.macros[0]).to be_a(Cornix::Models::Macro)
      expect(config.macros[0].sequence).to eq([1, 2, 3])
    end

    it 'タップダンスコレクションを正しく生成' do
      config = described_class.from_qmk(qmk_hash, position_map, keycode_converter)

      expect(config.tap_dances.size).to eq(1)
      expect(config.tap_dances[0]).to be_a(Cornix::Models::TapDance)
      expect(config.tap_dances[0].on_tap).to eq(4)
    end

    it 'コンボコレクションを正しく生成' do
      config = described_class.from_qmk(qmk_hash, position_map, keycode_converter)

      expect(config.combos.size).to eq(1)
      expect(config.combos[0]).to be_a(Cornix::Models::Combo)
      expect(config.combos[0].trigger_keys).to eq([20, 26])
    end

    it '空のマクロをスキップ' do
      qmk_hash['macro'] = [[], [1, 2], []]
      config = described_class.from_qmk(qmk_hash, position_map, keycode_converter)

      expect(config.macros.size).to eq(1)
      expect(config.macros[0].index).to eq(1)
    end

    it '空のタップダンスをスキップ' do
      qmk_hash['tap_dance'] = [[-1, -1, -1, -1, -1], [4, 5, 6, 7, 200]]
      config = described_class.from_qmk(qmk_hash, position_map, keycode_converter)

      expect(config.tap_dances.size).to eq(1)
      expect(config.tap_dances[0].index).to eq(1)
    end

    it '空のコンボをスキップ' do
      qmk_hash['combo'] = [[-1, -1, -1, -1, -1], [20, 26, -1, -1, 43]]
      config = described_class.from_qmk(qmk_hash, position_map, keycode_converter)

      expect(config.combos.size).to eq(1)
      expect(config.combos[0].index).to eq(1)
    end
  end

  describe '#to_qmk' do
    it 'VialConfigをQMK Hashに変換' do
      config = described_class.new(
        metadata: metadata,
        settings: settings,
        layers: layer_collection,
        macros: macro_collection,
        tap_dances: tap_dance_collection,
        combos: combo_collection
      )

      qmk_hash = config.to_qmk(
        position_map: position_map,
        keycode_converter: keycode_converter,
        reference_converter: nil
      )

      # 'keyboard'はto_qmkで出力されない（layout.vilに含まれないため）
      expect(qmk_hash['version']).to eq(1)
      expect(qmk_hash['uid']).to eq('TEST123')
      expect(qmk_hash).to have_key('layout')
      expect(qmk_hash).to have_key('encoder_layout')
      expect(qmk_hash).to have_key('macro')
      expect(qmk_hash).to have_key('tap_dance')
      expect(qmk_hash).to have_key('combo')
    end

    it 'レイヤー配列を正しく生成（10要素固定）' do
      config = described_class.new(
        metadata: metadata,
        settings: settings,
        layers: layer_collection,
        macros: macro_collection,
        tap_dances: tap_dance_collection,
        combos: combo_collection
      )

      qmk_hash = config.to_qmk(
        position_map: position_map,
        keycode_converter: keycode_converter,
        reference_converter: nil
      )

      expect(qmk_hash['layout'].size).to eq(10)
      expect(qmk_hash['encoder_layout'].size).to eq(10)
    end

    it 'マクロ配列を正しく生成（32要素固定）' do
      config = described_class.new(
        metadata: metadata,
        settings: settings,
        layers: layer_collection,
        macros: macro_collection,
        tap_dances: tap_dance_collection,
        combos: combo_collection
      )

      qmk_hash = config.to_qmk(
        position_map: position_map,
        keycode_converter: keycode_converter,
        reference_converter: nil
      )

      expect(qmk_hash['macro'].size).to eq(32)
      expect(qmk_hash['macro'][0]).to eq([1, 2, 3])
    end
  end

  describe '.from_yaml_hashes' do
    let(:metadata_hash) do
      {
        'keyboard' => 'test_keyboard',
        'version' => 1,
        'uid' => 'TEST123',
        'vendor_product_id' => '0x1234:0x5678',
        'product_id' => '0x5678',
        'matrix' => { 'rows' => 8, 'cols' => 7 },
        'vial_protocol' => 6,
        'via_protocol' => 12
      }
    end

    let(:settings_hash) do
      {}
    end

    let(:layers_hashes) do
      [
        {
          'name' => 'Base Layer',
          'description' => 'Test',
          'index' => 0,
          'mapping' => {
            'left_hand' => {
              'row0' => {},
              'row1' => {},
              'row2' => {},
              'row3' => {},
              'thumb_keys' => {}
            },
            'right_hand' => {
              'row0' => {},
              'row1' => {},
              'row2' => {},
              'row3' => {},
              'thumb_keys' => {}
            },
            'encoders' => {
              'left' => {},
              'right' => {}
            }
          }
        }
      ]
    end

    let(:macros_hashes) do
      [
        {
          'index' => 0,
          'name' => 'Test Macro',
          'description' => 'Test',
          'sequence' => [1, 2, 3]
        }
      ]
    end

    let(:tap_dances_hashes) do
      [
        {
          'index' => 0,
          'name' => 'Test TapDance',
          'description' => 'Test',
          'on_tap' => 4,
          'on_hold' => 5,
          'on_double_tap' => 6,
          'on_tap_hold' => 7,
          'tapping_term' => 200
        }
      ]
    end

    let(:combos_hashes) do
      [
        {
          'index' => 0,
          'name' => 'Test Combo',
          'description' => 'Test',
          'trigger_keys' => [20, 26],
          'output_key' => 43
        }
      ]
    end

    it 'YAML HashesからVialConfigを生成' do
      config = described_class.from_yaml_hashes(
        metadata_hash: metadata_hash,
        settings_hash: settings_hash,
        layers_hashes: layers_hashes,
        macros_hashes: macros_hashes,
        tap_dances_hashes: tap_dances_hashes,
        combos_hashes: combos_hashes,
        position_map: position_map,
        keycode_converter: keycode_converter,
        reference_converter: nil
      )

      expect(config.metadata.keyboard).to eq('test_keyboard')
      expect(config.layers.size).to eq(1)
      expect(config.macros.size).to eq(1)
      expect(config.tap_dances.size).to eq(1)
      expect(config.combos.size).to eq(1)
    end
  end

  describe '#to_yaml_hashes' do
    it 'VialConfigを複数のYAML Hashに変換' do
      config = described_class.new(
        metadata: metadata,
        settings: settings,
        layers: layer_collection,
        macros: macro_collection,
        tap_dances: tap_dance_collection,
        combos: combo_collection
      )

      yaml_hashes = config.to_yaml_hashes(
        keycode_converter: keycode_converter,
        reference_converter: nil
      )

      expect(yaml_hashes).to have_key(:metadata)
      expect(yaml_hashes).to have_key(:settings)
      expect(yaml_hashes).to have_key(:layers)
      expect(yaml_hashes).to have_key(:macros)
      expect(yaml_hashes).to have_key(:tap_dances)
      expect(yaml_hashes).to have_key(:combos)
    end

    it 'メタデータを正しく変換' do
      config = described_class.new(
        metadata: metadata,
        settings: settings,
        layers: layer_collection,
        macros: macro_collection,
        tap_dances: tap_dance_collection,
        combos: combo_collection
      )

      yaml_hashes = config.to_yaml_hashes(
        keycode_converter: keycode_converter,
        reference_converter: nil
      )

      expect(yaml_hashes[:metadata]['keyboard']).to eq('test_keyboard')
      expect(yaml_hashes[:metadata]['version']).to eq(1)
    end

    it 'レイヤー配列を正しく変換' do
      config = described_class.new(
        metadata: metadata,
        settings: settings,
        layers: layer_collection,
        macros: macro_collection,
        tap_dances: tap_dance_collection,
        combos: combo_collection
      )

      yaml_hashes = config.to_yaml_hashes(
        keycode_converter: keycode_converter,
        reference_converter: nil
      )

      expect(yaml_hashes[:layers].size).to eq(1)
      expect(yaml_hashes[:layers][0]['name']).to eq('Empty Layer')
    end

    it 'マクロ配列を正しく変換' do
      config = described_class.new(
        metadata: metadata,
        settings: settings,
        layers: layer_collection,
        macros: macro_collection,
        tap_dances: tap_dance_collection,
        combos: combo_collection
      )

      yaml_hashes = config.to_yaml_hashes(
        keycode_converter: keycode_converter,
        reference_converter: nil
      )

      expect(yaml_hashes[:macros].size).to eq(1)
      expect(yaml_hashes[:macros][0]['name']).to eq('Test Macro')
    end
  end

  describe 'round-trip conversion' do
    it 'QMK → VialConfig → QMK の往復変換' do
      qmk_hash = {
        'keyboard' => 'test_keyboard',  # from_qmkには影響しない（固定値'Cornix'を使用）
        'version' => 1,
        'uid' => 'TEST123',
        'vendor_product_id' => '0x1234:0x5678',
        'product_id' => '0x5678',
        'matrix' => { 'rows' => 8, 'cols' => 7 },
        'vial_protocol' => 6,
        'via_protocol' => 12,
        'layout' => [
          Array.new(8) { Array.new(7, -1) }
        ],
        'encoder_layout' => [
          Array.new(2) { Array.new(2, -1) }
        ],
        'macro' => [[1, 2, 3]],
        'tap_dance' => [[4, 5, 6, 7, 200]],
        'combo' => [[20, 26, -1, -1, 43]],
        'settings' => {}
      }

      config = described_class.from_qmk(qmk_hash, position_map, keycode_converter)
      result_hash = config.to_qmk(
        position_map: position_map,
        keycode_converter: keycode_converter,
        reference_converter: nil
      )

      # 'keyboard'はto_qmkで出力されない（layout.vilに含まれないため）
      expect(result_hash['version']).to eq(1)
      expect(result_hash['uid']).to eq('TEST123')
      expect(result_hash['layout'].size).to eq(10)
      expect(result_hash['macro'].size).to eq(32)
      expect(result_hash['macro'][0]).to eq([1, 2, 3])
    end
  end

  describe 'edge cases' do
    it '空のコレクションを許容' do
      config = described_class.new(
        metadata: metadata,
        settings: settings,
        layers: Cornix::Models::LayerCollection.new([]),
        macros: Cornix::Models::MacroCollection.new([]),
        tap_dances: Cornix::Models::TapDanceCollection.new([]),
        combos: Cornix::Models::ComboCollection.new([])
      )

      expect(config.layers.size).to eq(0)
      expect(config.macros.size).to eq(0)
      expect(config.tap_dances.size).to eq(0)
      expect(config.combos.size).to eq(0)
    end

    it 'QMK Hashにlayout/macro等が無い場合も処理可能' do
      minimal_qmk = {
        'keyboard' => 'test',
        'version' => 1,
        'uid' => 'TEST',
        'vendor_product_id' => '0x1234:0x5678',
        'product_id' => '0x5678',
        'matrix' => { 'rows' => 8, 'cols' => 7 },
        'vial_protocol' => 6,
        'via_protocol' => 12
      }

      config = described_class.from_qmk(minimal_qmk, position_map, keycode_converter)

      expect(config.layers.size).to eq(0)
      expect(config.macros.size).to eq(0)
      expect(config.tap_dances.size).to eq(0)
      expect(config.combos.size).to eq(0)
    end
  end
end
