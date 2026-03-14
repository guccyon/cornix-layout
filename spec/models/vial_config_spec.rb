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
    # Use system position_map.yaml for tests
    position_map_path = File.join(__dir__, '../../lib/cornix/position_map.yaml')
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
      sequence: [
        Cornix::Models::Macro::MacroStep.new(action: 'tap', keys: ['A']),
        Cornix::Models::Macro::MacroStep.new(action: 'delay', duration: 100)
      ]
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
          [['tap', 20], ['delay', 100]]
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
      expect(config.macros[0].sequence.size).to eq(2)
      expect(config.macros[0].sequence[0]).to be_a(Cornix::Models::Macro::MacroStep)
      expect(config.macros[0].sequence[0].action).to eq('tap')
      expect(config.macros[0].sequence[1].action).to eq('delay')
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
      qmk_hash['macro'] = [[], [['tap', 20], ['delay', 100]], []]
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
      expect(qmk_hash['macro'][0]).to eq([['tap', 'KC_A'], ['delay', 100]])
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
          'sequence' => [
            { 'action' => 'tap', 'keys' => ['A'] },
            { 'action' => 'delay', 'duration' => 100 }
          ]
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
        'macro' => [[['tap', 20], ['delay', 100]]],
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
      expect(result_hash['macro'][0]).to eq([['tap', 20], ['delay', 100]])
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

  describe '#validate!' do
    let(:context) do
      {
        keycode_converter: keycode_converter,
        reference_converter: nil,
        position_map: position_map
      }
    end

    it '全ての不具合を含む統合テスト - すべてエラーを検出すべき' do
      # 1. Layer with missing left_hand
      invalid_layer = Cornix::Models::Layer.new(
        name: 'Invalid Layer',
        description: '',
        index: 0,
        left_hand: nil,  # left_handが省略
        right_hand: Cornix::Models::Layer::HandMapping.empty(:right),
        encoders: Cornix::Models::Layer::EncoderMapping.new(left: {}, right: {})
      )

      # 2. Layer with invalid keycode
      invalid_key_mapping = Cornix::Models::Layer::KeyMapping.new(
        symbol: 'tab',
        keycode: 'InvalidKeyCodeAlias',  # 無効なキーコード
        logical_coord: { hand: :left, row: 0, col: 0 }
      )
      layer_with_invalid_keycode = Cornix::Models::Layer.new(
        name: 'Layer with invalid keycode',
        description: '',
        index: 1,
        left_hand: Cornix::Models::Layer::HandMapping.new(
          hand: :left,
          row0: [invalid_key_mapping],
          row1: [],
          row2: [],
          row3: [],
          thumb_keys: Cornix::Models::Layer::ThumbKeys.new
        ),
        right_hand: Cornix::Models::Layer::HandMapping.empty(:right),
        encoders: Cornix::Models::Layer::EncoderMapping.new(left: {}, right: {})
      )

      # 3. Layer with position_map に存在しないキー
      nonexistent_key_mapping = Cornix::Models::Layer::KeyMapping.new(
        symbol: 'NONEXISTENT_KEY',  # position_mapに存在しない
        keycode: 'Tab',
        logical_coord: { hand: :left, row: 0, col: 0 }
      )
      layer_with_nonexistent_key = Cornix::Models::Layer.new(
        name: 'Layer with nonexistent key',
        description: '',
        index: 2,
        left_hand: Cornix::Models::Layer::HandMapping.new(
          hand: :left,
          row0: [nonexistent_key_mapping],
          row1: [],
          row2: [],
          row3: [],
          thumb_keys: Cornix::Models::Layer::ThumbKeys.new
        ),
        right_hand: Cornix::Models::Layer::HandMapping.empty(:right),
        encoders: Cornix::Models::Layer::EncoderMapping.new(left: {}, right: {})
      )

      layer_collection_invalid = Cornix::Models::LayerCollection.new([
        invalid_layer,
        layer_with_invalid_keycode,
        layer_with_nonexistent_key
      ])

      # 4. Macro with keys but no action
      macro_step_no_action = Cornix::Models::Macro::MacroStep.new(
        action: nil,  # actionが省略
        keys: ['A', 'B']
      )
      macro_no_action = Cornix::Models::Macro.new(
        index: 0,
        name: 'Macro No Action',
        description: '',
        sequence: [macro_step_no_action]
      )

      # 5. Macro tap action without keys
      macro_step_no_keys = Cornix::Models::Macro::MacroStep.new(
        action: 'tap',
        keys: nil  # keysが省略
      )
      macro_no_keys = Cornix::Models::Macro.new(
        index: 1,
        name: 'Macro No Keys',
        description: '',
        sequence: [macro_step_no_keys]
      )

      # 6. Macro with invalid action
      macro_step_invalid_action = Cornix::Models::Macro::MacroStep.new(
        action: 'invalid_action',  # 無効なaction
        keys: ['A']
      )
      macro_invalid_action = Cornix::Models::Macro.new(
        index: 2,
        name: 'Macro Invalid Action',
        description: '',
        sequence: [macro_step_invalid_action]
      )

      macro_collection_invalid = Cornix::Models::MacroCollection.new([
        macro_no_action,
        macro_no_keys,
        macro_invalid_action
      ])

      # 7. Combo with missing output_key
      combo_no_output = Cornix::Models::Combo.new(
        index: 0,
        name: 'Combo No Output',
        description: '',
        trigger_keys: [20, 26],
        output_key: nil  # output_keyが省略
      )
      # メタデータ設定（ファイル名表示のため）
      combo_no_output.instance_variable_set(:@metadata, { file_path: 'config/combos/00_invalid.yaml' })

      combo_collection_invalid = Cornix::Models::ComboCollection.new([combo_no_output])

      # VialConfig作成
      vial_config = described_class.new(
        metadata: metadata,
        settings: settings,
        layers: layer_collection_invalid,
        macros: macro_collection_invalid,
        tap_dances: Cornix::Models::TapDanceCollection.new([]),
        combos: combo_collection_invalid
      )

      # 検証実行（collect mode）
      errors = vial_config.validate!(context, mode: :collect)

      # デバッグ: 全エラーを出力
      puts "\n=== All Errors (#{errors.size}) ===\n#{errors.join("\n")}\n==="

      # すべてのエラーが検出されていることを確認
      errors_text = errors.join("\n")

      # Layer関連
      expect(errors_text).to include('left_hand'), "left_handが省略されているエラーが検出されていません"
      expect(errors_text).to include('InvalidKeyCodeAlias'), "無効なキーコードエラーが検出されていません"
      expect(errors_text).to include('NONEXISTENT_KEY'), "position_mapに存在しないキーのエラーが検出されていません"

      # Macro関連
      expect(errors_text).to include('action'), "actionが省略されているエラーが検出されていません"
      expect(errors_text).to include('keys'), "keysが省略されているエラーが検出されていません"
      expect(errors_text).to match(/action.*must be one of/), "無効なactionのエラーが検出されていません"

      # Combo関連
      expect(errors_text).to include('output_key'), "output_keyが省略されているエラーが検出されていません"
      expect(errors_text).to include('00_invalid.yaml'), "Comboのファイル名が表示されていません"

      # エラーメッセージにファイル名やコンテキスト情報が含まれているか確認
      expect(errors_text).to match(/layer|Layer/i), "Layerに関するエラーが識別できません"
      expect(errors_text).to match(/macro|Macro/i), "Macroに関するエラーが識別できません"
      expect(errors_text).to match(/combo|Combo/i), "Comboに関するエラーが識別できません"
    end
  end
end
