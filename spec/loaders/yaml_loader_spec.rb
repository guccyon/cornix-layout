# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../lib/cornix/loaders/yaml_loader'
require_relative '../../lib/cornix/position_map'
require_relative '../../lib/cornix/converters/keycode_converter'
require 'fileutils'
require 'tempfile'

RSpec.describe Cornix::Loaders::YamlLoader do
  let(:position_map) do
    position_map_path = File.join(__dir__, '../fixtures/position_map.yaml')
    Cornix::PositionMap.new(position_map_path)
  end

  let(:keycode_converter) do
    aliases_path = File.join(__dir__, '../../lib/cornix/keycode_aliases.yaml')
    Cornix::Converters::KeycodeConverter.new(aliases_path)
  end

  describe '#initialize' do
    it 'config ディレクトリのパスを保持' do
      loader = described_class.new('path/to/config')

      expect(loader.instance_variable_get(:@config_dir)).to eq('path/to/config')
    end
  end

  describe '#load' do
    let(:temp_dir) { Dir.mktmpdir }

    after do
      FileUtils.rm_rf(temp_dir)
    end

    it 'config ディレクトリが存在しない場合はエラー' do
      loader = described_class.new('nonexistent_dir')

      expect {
        loader.load(position_map: position_map, keycode_converter: keycode_converter, reference_converter: nil, validate: false)
      }.to raise_error(/Config directory not found/)
    end

    it 'メタデータファイルを読み込む' do
      FileUtils.mkdir_p("#{temp_dir}/settings")
      FileUtils.mkdir_p("#{temp_dir}/layers")
      FileUtils.mkdir_p("#{temp_dir}/macros")
      FileUtils.mkdir_p("#{temp_dir}/tap_dance")
      FileUtils.mkdir_p("#{temp_dir}/combos")

      File.write("#{temp_dir}/metadata.yaml", YAML.dump({
        'keyboard' => 'Cornix',
        'version' => 1,
        'uid' => 'TEST123',
        'vendor_product_id' => '0x1234:0x5678',
        'product_id' => '0x5678',
        'matrix' => { 'rows' => 8, 'cols' => 7 },
        'vial_protocol' => 6,
        'via_protocol' => 12
      }))

      File.write("#{temp_dir}/settings/qmk_settings.yaml", YAML.dump({}))

      loader = described_class.new(temp_dir)
      config = loader.load(position_map: position_map, keycode_converter: keycode_converter, reference_converter: nil, validate: false)

      expect(config).to be_a(Cornix::Models::VialConfig)
      expect(config.metadata.keyboard).to eq('Cornix')
      expect(config.metadata.version).to eq(1)
    end

    it 'レイヤーファイルを読み込む' do
      FileUtils.mkdir_p("#{temp_dir}/settings")
      FileUtils.mkdir_p("#{temp_dir}/layers")
      FileUtils.mkdir_p("#{temp_dir}/macros")
      FileUtils.mkdir_p("#{temp_dir}/tap_dance")
      FileUtils.mkdir_p("#{temp_dir}/combos")

      File.write("#{temp_dir}/metadata.yaml", YAML.dump({
        'keyboard' => 'Cornix',
        'version' => 1,
        'uid' => 'TEST123',
        'vendor_product_id' => '0x1234:0x5678',
        'product_id' => '0x5678',
        'matrix' => { 'rows' => 8, 'cols' => 7 },
        'vial_protocol' => 6,
        'via_protocol' => 12
      }))

      File.write("#{temp_dir}/settings/qmk_settings.yaml", YAML.dump({}))

      File.write("#{temp_dir}/layers/0_base.yaml", YAML.dump({
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
      }))

      loader = described_class.new(temp_dir)
      config = loader.load(position_map: position_map, keycode_converter: keycode_converter, reference_converter: nil, validate: false)

      expect(config.layers).to be_a(Cornix::Models::LayerCollection)
      expect(config.layers.size).to eq(1)
      expect(config.layers[0].name).to eq('Base Layer')
    end

    it 'マクロファイルを読み込む' do
      FileUtils.mkdir_p("#{temp_dir}/settings")
      FileUtils.mkdir_p("#{temp_dir}/layers")
      FileUtils.mkdir_p("#{temp_dir}/macros")
      FileUtils.mkdir_p("#{temp_dir}/tap_dance")
      FileUtils.mkdir_p("#{temp_dir}/combos")

      File.write("#{temp_dir}/metadata.yaml", YAML.dump({
        'keyboard' => 'Cornix',
        'version' => 1,
        'uid' => 'TEST123',
        'vendor_product_id' => '0x1234:0x5678',
        'product_id' => '0x5678',
        'matrix' => { 'rows' => 8, 'cols' => 7 },
        'vial_protocol' => 6,
        'via_protocol' => 12
      }))

      File.write("#{temp_dir}/settings/qmk_settings.yaml", YAML.dump({}))

      File.write("#{temp_dir}/macros/00_test.yaml", YAML.dump({
        'index' => 0,
        'name' => 'Test Macro',
        'description' => 'Test',
        'sequence' => [
          {
            'action' => 'tap',
            'keys' => ['A', 'B']
          }
        ]
      }))

      loader = described_class.new(temp_dir)
      config = loader.load(position_map: position_map, keycode_converter: keycode_converter, reference_converter: nil, validate: false)

      expect(config.macros).to be_a(Cornix::Models::MacroCollection)
      expect(config.macros.size).to eq(1)
      expect(config.macros[0].name).to eq('Test Macro')
    end

    it 'タップダンスファイルを読み込む' do
      FileUtils.mkdir_p("#{temp_dir}/settings")
      FileUtils.mkdir_p("#{temp_dir}/layers")
      FileUtils.mkdir_p("#{temp_dir}/macros")
      FileUtils.mkdir_p("#{temp_dir}/tap_dance")
      FileUtils.mkdir_p("#{temp_dir}/combos")

      File.write("#{temp_dir}/metadata.yaml", YAML.dump({
        'keyboard' => 'Cornix',
        'version' => 1,
        'uid' => 'TEST123',
        'vendor_product_id' => '0x1234:0x5678',
        'product_id' => '0x5678',
        'matrix' => { 'rows' => 8, 'cols' => 7 },
        'vial_protocol' => 6,
        'via_protocol' => 12
      }))

      File.write("#{temp_dir}/settings/qmk_settings.yaml", YAML.dump({}))

      File.write("#{temp_dir}/tap_dance/00_test.yaml", YAML.dump({
        'index' => 0,
        'name' => 'Test TapDance',
        'description' => 'Test',
        'on_tap' => 4,
        'on_hold' => 5,
        'on_double_tap' => 6,
        'on_tap_hold' => 7,
        'tapping_term' => 200
      }))

      loader = described_class.new(temp_dir)
      config = loader.load(position_map: position_map, keycode_converter: keycode_converter, reference_converter: nil, validate: false)

      expect(config.tap_dances).to be_a(Cornix::Models::TapDanceCollection)
      expect(config.tap_dances.size).to eq(1)
      expect(config.tap_dances[0].name).to eq('Test TapDance')
    end

    it 'コンボファイルを読み込む' do
      FileUtils.mkdir_p("#{temp_dir}/settings")
      FileUtils.mkdir_p("#{temp_dir}/layers")
      FileUtils.mkdir_p("#{temp_dir}/macros")
      FileUtils.mkdir_p("#{temp_dir}/tap_dance")
      FileUtils.mkdir_p("#{temp_dir}/combos")

      File.write("#{temp_dir}/metadata.yaml", YAML.dump({
        'keyboard' => 'Cornix',
        'version' => 1,
        'uid' => 'TEST123',
        'vendor_product_id' => '0x1234:0x5678',
        'product_id' => '0x5678',
        'matrix' => { 'rows' => 8, 'cols' => 7 },
        'vial_protocol' => 6,
        'via_protocol' => 12
      }))

      File.write("#{temp_dir}/settings/qmk_settings.yaml", YAML.dump({}))

      File.write("#{temp_dir}/combos/00_test.yaml", YAML.dump({
        'index' => 0,
        'name' => 'Test Combo',
        'description' => 'Test',
        'trigger_keys' => [20, 26],
        'output_key' => 43
      }))

      loader = described_class.new(temp_dir)
      config = loader.load(position_map: position_map, keycode_converter: keycode_converter, reference_converter: nil, validate: false)

      expect(config.combos).to be_a(Cornix::Models::ComboCollection)
      expect(config.combos.size).to eq(1)
      expect(config.combos[0].name).to eq('Test Combo')
    end

    it 'ファイルが存在しない場合はエラー' do
      FileUtils.mkdir_p(temp_dir)

      loader = described_class.new(temp_dir)

      # Metadata is required, so missing files should raise an error
      expect {
        loader.load(position_map: position_map, keycode_converter: keycode_converter, reference_converter: nil, validate: false)
      }.to raise_error(ArgumentError, /keyboard cannot be nil/)
    end

    it '実際の config/ ディレクトリを読み込める' do
      config_path = File.join(__dir__, '../../config')
      skip "config/ not found" unless Dir.exist?(config_path)

      loader = described_class.new(config_path)
      config = loader.load(position_map: position_map, keycode_converter: keycode_converter, reference_converter: nil, validate: false)

      expect(config).to be_a(Cornix::Models::VialConfig)
      # 実際のファイルの値を使用（'cornix' 小文字）
      expect(config.metadata.keyboard).to be_a(String)
      expect(config.layers).to be_a(Cornix::Models::LayerCollection)
      expect(config.macros).to be_a(Cornix::Models::MacroCollection)
    end
  end

  describe 'integration' do
    let(:temp_dir) { Dir.mktmpdir }

    after do
      FileUtils.rm_rf(temp_dir)
    end

    it 'VialConfig から to_yaml_hashes で元のハッシュを再現可能' do
      FileUtils.mkdir_p("#{temp_dir}/settings")
      FileUtils.mkdir_p("#{temp_dir}/layers")
      FileUtils.mkdir_p("#{temp_dir}/macros")
      FileUtils.mkdir_p("#{temp_dir}/tap_dance")
      FileUtils.mkdir_p("#{temp_dir}/combos")

      File.write("#{temp_dir}/metadata.yaml", YAML.dump({
        'keyboard' => 'Cornix',
        'version' => 1,
        'uid' => 'TEST123',
        'vendor_product_id' => '0x1234:0x5678',
        'product_id' => '0x5678',
        'matrix' => { 'rows' => 8, 'cols' => 7 },
        'vial_protocol' => 6,
        'via_protocol' => 12
      }))

      File.write("#{temp_dir}/settings/qmk_settings.yaml", YAML.dump({}))

      File.write("#{temp_dir}/layers/0_base.yaml", YAML.dump({
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
      }))

      loader = described_class.new(temp_dir)
      config = loader.load(position_map: position_map, keycode_converter: keycode_converter, reference_converter: nil, validate: false)

      yaml_hashes = config.to_yaml_hashes(keycode_converter: keycode_converter, reference_converter: nil)

      expect(yaml_hashes[:metadata]['keyboard']).to eq('Cornix')
      expect(yaml_hashes[:metadata]['version']).to eq(1)
      expect(yaml_hashes[:layers].size).to eq(1)
      expect(yaml_hashes[:layers][0]['name']).to eq('Base Layer')
    end
  end
end
