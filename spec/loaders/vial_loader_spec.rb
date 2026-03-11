# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../lib/cornix/loaders/vial_loader'
require_relative '../../lib/cornix/position_map'
require_relative '../../lib/cornix/converters/keycode_converter'
require 'json'
require 'tempfile'

RSpec.describe Cornix::Loaders::VialLoader do
  let(:position_map) do
    position_map_path = File.join(__dir__, '../../config/position_map.yaml')
    Cornix::PositionMap.new(position_map_path)
  end

  let(:keycode_converter) do
    aliases_path = File.join(__dir__, '../../lib/cornix/keycode_aliases.yaml')
    Cornix::Converters::KeycodeConverter.new(aliases_path)
  end

  let(:minimal_qmk_hash) do
    {
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
  end

  describe '#initialize' do
    it 'layout.vil のパスを保持' do
      loader = described_class.new('path/to/layout.vil')

      expect(loader.instance_variable_get(:@vil_path)).to eq('path/to/layout.vil')
    end
  end

  describe '#load' do
    it 'JSONファイルを読み込んで VialConfig に変換' do
      Tempfile.create(['test_layout', '.vil']) do |file|
        file.write(JSON.generate(minimal_qmk_hash))
        file.flush

        loader = described_class.new(file.path)
        config = loader.load(position_map: position_map, keycode_converter: keycode_converter)

        expect(config).to be_a(Cornix::Models::VialConfig)
        expect(config.metadata.keyboard).to eq('Cornix')
        expect(config.metadata.version).to eq(1)
        expect(config.metadata.uid).to eq('TEST123')
      end
    end

    it 'レイヤーを正しく読み込む' do
      Tempfile.create(['test_layout', '.vil']) do |file|
        file.write(JSON.generate(minimal_qmk_hash))
        file.flush

        loader = described_class.new(file.path)
        config = loader.load(position_map: position_map, keycode_converter: keycode_converter)

        expect(config.layers).to be_a(Cornix::Models::LayerCollection)
        expect(config.layers.size).to eq(1)
      end
    end

    it 'マクロを正しく読み込む' do
      Tempfile.create(['test_layout', '.vil']) do |file|
        file.write(JSON.generate(minimal_qmk_hash))
        file.flush

        loader = described_class.new(file.path)
        config = loader.load(position_map: position_map, keycode_converter: keycode_converter)

        expect(config.macros).to be_a(Cornix::Models::MacroCollection)
        expect(config.macros.size).to eq(1)
        expect(config.macros[0].sequence).to eq([1, 2, 3])
      end
    end

    it 'タップダンスを正しく読み込む' do
      Tempfile.create(['test_layout', '.vil']) do |file|
        file.write(JSON.generate(minimal_qmk_hash))
        file.flush

        loader = described_class.new(file.path)
        config = loader.load(position_map: position_map, keycode_converter: keycode_converter)

        expect(config.tap_dances).to be_a(Cornix::Models::TapDanceCollection)
        expect(config.tap_dances.size).to eq(1)
        expect(config.tap_dances[0].on_tap).to eq(4)
      end
    end

    it 'コンボを正しく読み込む' do
      Tempfile.create(['test_layout', '.vil']) do |file|
        file.write(JSON.generate(minimal_qmk_hash))
        file.flush

        loader = described_class.new(file.path)
        config = loader.load(position_map: position_map, keycode_converter: keycode_converter)

        expect(config.combos).to be_a(Cornix::Models::ComboCollection)
        expect(config.combos.size).to eq(1)
        expect(config.combos[0].trigger_keys).to eq([20, 26])
      end
    end

    it 'ファイルが存在しない場合はエラー' do
      loader = described_class.new('nonexistent.vil')

      expect {
        loader.load(position_map: position_map, keycode_converter: keycode_converter)
      }.to raise_error(/File not found/)
    end

    it '不正なJSONの場合はエラー' do
      Tempfile.create(['invalid', '.vil']) do |file|
        file.write('invalid json {')
        file.flush

        loader = described_class.new(file.path)

        expect {
          loader.load(position_map: position_map, keycode_converter: keycode_converter)
        }.to raise_error(JSON::ParserError)
      end
    end

    it '実際の tmp/layout.vil を読み込める' do
      vil_path = File.join(__dir__, '../../tmp/layout.vil')
      skip "tmp/layout.vil not found" unless File.exist?(vil_path)

      loader = described_class.new(vil_path)
      config = loader.load(position_map: position_map, keycode_converter: keycode_converter)

      expect(config).to be_a(Cornix::Models::VialConfig)
      expect(config.metadata.keyboard).to eq('Cornix')
      expect(config.layers).to be_a(Cornix::Models::LayerCollection)
      expect(config.macros).to be_a(Cornix::Models::MacroCollection)
    end
  end

  describe 'integration' do
    it 'VialConfig から to_qmk で元のハッシュを再現可能' do
      Tempfile.create(['test_layout', '.vil']) do |file|
        file.write(JSON.generate(minimal_qmk_hash))
        file.flush

        loader = described_class.new(file.path)
        config = loader.load(position_map: position_map, keycode_converter: keycode_converter)

        qmk_hash = config.to_qmk(
          position_map: position_map,
          keycode_converter: keycode_converter,
          reference_converter: nil
        )

        expect(qmk_hash['version']).to eq(1)
        expect(qmk_hash['uid']).to eq('TEST123')
        expect(qmk_hash['layout'].size).to eq(10)
        expect(qmk_hash['macro'].size).to eq(32)
      end
    end
  end
end
