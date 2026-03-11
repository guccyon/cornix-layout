# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../lib/cornix/writers/vial_writer'
require_relative '../../lib/cornix/models/vial_config'
require_relative '../../lib/cornix/position_map'
require_relative '../../lib/cornix/converters/keycode_converter'
require 'json'
require 'tempfile'

RSpec.describe Cornix::Writers::VialWriter do
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
    let(:temp_file) { Tempfile.new(['layout', '.vil']) }

    after do
      temp_file.close
      temp_file.unlink
    end

    it 'VialConfig を JSON として書き込み' do
      writer = described_class.new
      writer.write(
        vial_config,
        temp_file.path,
        position_map: position_map,
        keycode_converter: keycode_converter,
        reference_converter: nil
      )

      expect(File.exist?(temp_file.path)).to be true

      # JSON として妥当か
      vil_data = JSON.parse(File.read(temp_file.path))
      expect(vil_data).to be_a(Hash)
    end

    it 'Pretty print された JSON を生成' do
      writer = described_class.new
      writer.write(
        vial_config,
        temp_file.path,
        position_map: position_map,
        keycode_converter: keycode_converter,
        reference_converter: nil
      )

      content = File.read(temp_file.path)

      # Pretty print されている（改行とインデントがある）
      expect(content).to include("\n")
      expect(content).to match(/^\s{2,}/)  # インデントがある
    end

    it '指定されたパスに出力' do
      custom_path = File.join(Dir.tmpdir, 'custom_layout.vil')
      writer = described_class.new
      writer.write(
        vial_config,
        custom_path,
        position_map: position_map,
        keycode_converter: keycode_converter,
        reference_converter: nil
      )

      expect(File.exist?(custom_path)).to be true
      File.delete(custom_path)
    end

    it 'keycode_converter を使用してキーコードを変換' do
      writer = described_class.new

      # keycode_converter が nil の場合はエラー
      expect {
        writer.write(
          vial_config,
          temp_file.path,
          position_map: position_map,
          keycode_converter: nil,
          reference_converter: nil
        )
      }.to raise_error
    end

    it 'position_map を使用して配列構造を生成' do
      writer = described_class.new
      writer.write(
        vial_config,
        temp_file.path,
        position_map: position_map,
        keycode_converter: keycode_converter,
        reference_converter: nil
      )

      vil_data = JSON.parse(File.read(temp_file.path))

      # position_map に基づく 8×7 配列構造
      expect(vil_data['layout']).to be_a(Array)
      expect(vil_data['layout'].size).to eq(10)  # 10 layers
      expect(vil_data['layout'].first).to be_a(Array)
      expect(vil_data['layout'].first.size).to eq(8)  # 8 rows
      expect(vil_data['layout'].first.first).to be_a(Array)
      expect(vil_data['layout'].first.first.size).to eq(7)  # 7 cols
    end
  end

  describe 'integration' do
    let(:temp_file) { Tempfile.new(['layout', '.vil']) }

    after do
      temp_file.close
      temp_file.unlink
    end

    it '書き込んだファイルを VialLoader で読み込める' do
      writer = described_class.new
      writer.write(
        vial_config,
        temp_file.path,
        position_map: position_map,
        keycode_converter: keycode_converter,
        reference_converter: nil
      )

      # VialLoader で読み込み
      require_relative '../../lib/cornix/loaders/vial_loader'
      loader = Cornix::Loaders::VialLoader.new(temp_file.path)
      loaded_config = loader.load(
        position_map: position_map,
        keycode_converter: keycode_converter,
        reference_converter: nil
      )

      expect(loaded_config).to be_a(Cornix::Models::VialConfig)
      # keyboard is fixed to 'Cornix' when loading from QMK (layout.vil doesn't store it)
      expect(loaded_config.metadata.keyboard).to eq('Cornix')
    end
  end
end
