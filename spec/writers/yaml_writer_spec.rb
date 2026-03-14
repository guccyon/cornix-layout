# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../lib/cornix/writers/yaml_writer'
require_relative '../../lib/cornix/models/vial_config'
require_relative '../../lib/cornix/position_map'
require_relative '../../lib/cornix/converters/keycode_converter'
require 'fileutils'
require 'tempfile'

RSpec.describe Cornix::Writers::YamlWriter do
  let(:keycode_converter) do
    aliases_path = File.join(__dir__, '../../lib/cornix/keycode_aliases.yaml')
    Cornix::Converters::KeycodeConverter.new(aliases_path)
  end

  let(:metadata) do
    Cornix::Models::Metadata.new(
      keyboard: 'test_keyboard',
      version: 1,
      uid: 'TEST123',
      vendor_product_id: '0x1234',
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
      name: 'Base Layer',
      description: 'Test layer',
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
        Cornix::Models::Macro::MacroStep.new(
          action: 'tap',
          keys: ['A', 'B']
        )
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

  let(:vial_config) do
    Cornix::Models::VialConfig.new(
      metadata: metadata,
      settings: settings,
      layers: layer_collection,
      macros: macro_collection,
      tap_dances: tap_dance_collection,
      combos: combo_collection
    )
  end

  describe '#write' do
    let(:temp_dir) { Dir.mktmpdir }

    after do
      FileUtils.rm_rf(temp_dir)
    end

    it 'ディレクトリ構造を正しく作成' do
      writer = described_class.new(temp_dir)
      writer.write(
        vial_config,
        keycode_converter: keycode_converter,
        reference_converter: nil
      )

      expect(Dir.exist?("#{temp_dir}/settings")).to be true
      expect(Dir.exist?("#{temp_dir}/layers")).to be true
      expect(Dir.exist?("#{temp_dir}/macros")).to be true
      expect(Dir.exist?("#{temp_dir}/tap_dance")).to be true
      expect(Dir.exist?("#{temp_dir}/combos")).to be true
    end

    it 'メタデータファイルを生成' do
      writer = described_class.new(temp_dir)
      writer.write(
        vial_config,
        keycode_converter: keycode_converter,
        reference_converter: nil
      )

      metadata_file = "#{temp_dir}/metadata.yaml"
      expect(File.exist?(metadata_file)).to be true

      loaded = YAML.load_file(metadata_file)
      expect(loaded['keyboard']).to eq('test_keyboard')
      expect(loaded['version']).to eq(1)
      expect(loaded['uid']).to eq('TEST123')
    end

    it '設定ファイルを生成' do
      writer = described_class.new(temp_dir)
      writer.write(
        vial_config,
        keycode_converter: keycode_converter,
        reference_converter: nil
      )

      settings_file = "#{temp_dir}/settings/qmk_settings.yaml"
      expect(File.exist?(settings_file)).to be true
    end

    it 'レイヤーファイルを生成' do
      writer = described_class.new(temp_dir)
      writer.write(
        vial_config,
        keycode_converter: keycode_converter,
        reference_converter: nil
      )

      layer_files = Dir.glob("#{temp_dir}/layers/*.yaml")
      expect(layer_files.size).to eq(1)

      layer_file = layer_files.first
      loaded = YAML.load_file(layer_file)
      expect(loaded['name']).to eq('Base Layer')
      expect(loaded['description']).to eq('Test layer')
    end

    it 'マクロファイルを生成' do
      writer = described_class.new(temp_dir)
      writer.write(
        vial_config,
        keycode_converter: keycode_converter,
        reference_converter: nil
      )

      macro_files = Dir.glob("#{temp_dir}/macros/*.yaml")
      expect(macro_files.size).to eq(1)

      macro_file = macro_files.first
      expect(File.basename(macro_file)).to eq('00_test_macro.yaml')

      loaded = YAML.load_file(macro_file)
      expect(loaded['name']).to eq('Test Macro')
      expect(loaded['description']).to eq('Test')
      expect(loaded['sequence']).to be_a(Array)
      expect(loaded['sequence'].size).to eq(1)
      expect(loaded['sequence'][0]).to be_a(Hash)
      expect(loaded['sequence'][0]['action']).to eq('tap')
      expect(loaded['sequence'][0]['keys']).to eq(['A', 'B'])
    end

    it 'タップダンスファイルを生成' do
      writer = described_class.new(temp_dir)
      writer.write(
        vial_config,
        keycode_converter: keycode_converter,
        reference_converter: nil
      )

      tap_dance_files = Dir.glob("#{temp_dir}/tap_dance/*.yaml")
      expect(tap_dance_files.size).to eq(1)

      tap_dance_file = tap_dance_files.first
      expect(File.basename(tap_dance_file)).to eq('00_test_tapdance.yaml')

      loaded = YAML.load_file(tap_dance_file)
      expect(loaded['name']).to eq('Test TapDance')
      expect(loaded['on_tap']).to eq(4)
      expect(loaded['tapping_term']).to eq(200)
    end

    it 'コンボファイルを生成' do
      writer = described_class.new(temp_dir)
      writer.write(
        vial_config,
        keycode_converter: keycode_converter,
        reference_converter: nil
      )

      combo_files = Dir.glob("#{temp_dir}/combos/*.yaml")
      expect(combo_files.size).to eq(1)

      combo_file = combo_files.first
      expect(File.basename(combo_file)).to eq('00_test_combo.yaml')

      loaded = YAML.load_file(combo_file)
      expect(loaded['name']).to eq('Test Combo')
      expect(loaded['trigger_keys']).to eq([20, 26])
      expect(loaded['output_key']).to eq(43)
    end

    it 'ファイル名を正しくサニタイズ' do
      writer = described_class.new(temp_dir)

      # 特殊文字を含むマクロ
      special_macro = Cornix::Models::Macro.new(
        index: 1,
        name: 'Copy Line (Cmd+C)',
        description: 'Test',
        sequence: [
          Cornix::Models::Macro::MacroStep.new(
            action: 'tap',
            keys: ['A']
          )
        ]
      )
      special_macro_collection = Cornix::Models::MacroCollection.new([special_macro])

      special_vial_config = Cornix::Models::VialConfig.new(
        metadata: metadata,
        settings: settings,
        layers: layer_collection,
        macros: special_macro_collection,
        tap_dances: tap_dance_collection,
        combos: combo_collection
      )

      writer.write(
        special_vial_config,
        keycode_converter: keycode_converter,
        reference_converter: nil
      )

      macro_files = Dir.glob("#{temp_dir}/macros/*.yaml")
      expect(macro_files.size).to eq(1)
      expect(File.basename(macro_files.first)).to eq('01_copy_line_cmd_c.yaml')
    end
  end

  describe 'integration' do
    let(:temp_dir) { Dir.mktmpdir }

    after do
      FileUtils.rm_rf(temp_dir)
    end

    it 'YamlLoader で書き込んだファイルを読み込める' do
      writer = described_class.new(temp_dir)
      writer.write(
        vial_config,
        keycode_converter: keycode_converter,
        reference_converter: nil
      )

      # YamlLoader で読み込み
      require_relative '../../lib/cornix/loaders/yaml_loader'
      position_map_path = File.join(__dir__, '../fixtures/position_map.yaml')
      position_map = Cornix::PositionMap.new(position_map_path)

      loader = Cornix::Loaders::YamlLoader.new(temp_dir)
      loaded_config = loader.load(
        position_map: position_map,
        keycode_converter: keycode_converter,
        reference_converter: nil
      )

      expect(loaded_config).to be_a(Cornix::Models::VialConfig)
      expect(loaded_config.metadata.keyboard).to eq('test_keyboard')
      expect(loaded_config.layers.size).to eq(1)
      expect(loaded_config.macros.size).to eq(1)
      expect(loaded_config.tap_dances.size).to eq(1)
      expect(loaded_config.combos.size).to eq(1)
    end
  end
end
