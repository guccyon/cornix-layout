# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require_relative '../../../lib/cornix/models/layer/hand_mapping'
require_relative '../../../lib/cornix/position_map'
require_relative '../../../lib/cornix/converters/keycode_converter'
require_relative '../../../lib/cornix/converters/reference_converter'

RSpec.describe Cornix::Models::Layer::HandMapping do
  let(:aliases_path) { File.join(__dir__, '../../../lib/cornix/keycode_aliases.yaml') }
  let(:keycode_converter) { Cornix::Converters::KeycodeConverter.new(aliases_path) }
  let(:position_map_path) { File.join(__dir__, '../../../lib/cornix/position_map.yaml') }
  let(:position_map) { Cornix::PositionMap.new(position_map_path) }
  let(:config_dir) { File.join(__dir__, '../../fixtures/config') }
  let(:reference_converter) { Cornix::Converters::ReferenceConverter.new(config_dir) }

  before do
    FileUtils.mkdir_p("#{config_dir}/macros")
    File.write("#{config_dir}/macros/00_test_macro.yml", <<~YAML)
      name: Test Macro
      index: 0
      sequence: [{delay: 0, keycodes: [KC_H, KC_I]}]
    YAML
  end

  after do
    FileUtils.rm_rf(config_dir)
  end

  describe '#initialize' do
    it 'creates HandMapping with left hand' do
      hand_mapping = described_class.new(
        hand: :left,
        row0: [],
        row1: [],
        row2: [],
        row3: [],
        thumb_keys: Cornix::Models::Layer::ThumbKeys.new
      )

      expect(hand_mapping.hand).to eq(:left)
      expect(hand_mapping.row0).to eq([])
      expect(hand_mapping.thumb_keys).to be_a(Cornix::Models::Layer::ThumbKeys)
    end

    it 'creates HandMapping with right hand' do
      hand_mapping = described_class.new(
        hand: :right,
        row0: [],
        row1: [],
        row2: [],
        row3: [],
        thumb_keys: Cornix::Models::Layer::ThumbKeys.new
      )

      expect(hand_mapping.hand).to eq(:right)
    end

    it 'creates HandMapping with key mappings' do
      key1 = Cornix::Models::Layer::KeyMapping.new(symbol: 'Q', keycode: 'Tab', logical_coord: { hand: :left, row: 0, col: 1 })
      key2 = Cornix::Models::Layer::KeyMapping.new(symbol: 'W', keycode: 'Space', logical_coord: { hand: :left, row: 0, col: 2 })

      hand_mapping = described_class.new(
        hand: :left,
        row0: [key1, key2],
        row1: [],
        row2: [],
        row3: [],
        thumb_keys: Cornix::Models::Layer::ThumbKeys.new
      )

      expect(hand_mapping.row0.size).to eq(2)
      expect(hand_mapping.row0[0].symbol).to eq('Q')
      expect(hand_mapping.row0[1].symbol).to eq('W')
    end
  end

  describe '#all_keys' do
    it 'returns all key mappings including thumb keys' do
      key1 = Cornix::Models::Layer::KeyMapping.new(symbol: 'Q', keycode: 'Tab', logical_coord: { hand: :left, row: 0, col: 1 })
      key2 = Cornix::Models::Layer::KeyMapping.new(symbol: 'left', keycode: 'Space', logical_coord: { hand: :left, row: 3, col: 3 })
      thumb_keys = Cornix::Models::Layer::ThumbKeys.new(left: key2)

      hand_mapping = described_class.new(
        hand: :left,
        row0: [key1],
        row1: [],
        row2: [],
        row3: [],
        thumb_keys: thumb_keys
      )

      all = hand_mapping.all_keys
      expect(all.size).to eq(4)  # key1 + NULL_KEY + NULL_KEY + NULL_KEY (thumb_keys.to_array の3要素)
      expect(all[0]).to eq(key1)
      expect(all[1]).to eq(key2)
    end
  end

  describe '.empty' do
    it 'creates empty HandMapping for left hand' do
      hand_mapping = described_class.empty(:left)

      expect(hand_mapping.hand).to eq(:left)
      expect(hand_mapping.row0).to eq([])
      expect(hand_mapping.row1).to eq([])
      expect(hand_mapping.row2).to eq([])
      expect(hand_mapping.row3).to eq([])
      expect(hand_mapping.thumb_keys).to be_a(Cornix::Models::Layer::ThumbKeys)
    end

    it 'creates empty HandMapping for right hand' do
      hand_mapping = described_class.empty(:right)
      expect(hand_mapping.hand).to eq(:right)
    end
  end

  describe '.from_yaml_hash' do
    it 'creates HandMapping from YAML hash (left hand)' do
      yaml_hand = {
        'row0' => { 'Q' => 'Tab', 'W' => 'Space' },
        'row1' => { 'A' => 'Enter' },
        'row2' => {},
        'row3' => {},
        'thumb_keys' => { 'left' => 'Ctrl', 'right' => 'Alt' }
      }

      hand_mapping = described_class.from_yaml_hash(hand: :left, yaml_hand: yaml_hand, position_map: position_map)

      expect(hand_mapping.hand).to eq(:left)
      expect(hand_mapping.row0.size).to eq(2)
      expect(hand_mapping.row0[0].symbol).to eq('Q')
      expect(hand_mapping.row0[0].keycode.to_s).to eq('Tab')
      expect(hand_mapping.row0[1].symbol).to eq('W')
      expect(hand_mapping.row0[1].keycode.to_s).to eq('Space')
      expect(hand_mapping.row1.size).to eq(1)
      expect(hand_mapping.row1[0].symbol).to eq('A')
      expect(hand_mapping.row1[0].keycode.to_s).to eq('Enter')
      expect(hand_mapping.thumb_keys.left.symbol).to eq('left')
      expect(hand_mapping.thumb_keys.left.keycode.to_s).to eq('Ctrl')
      expect(hand_mapping.thumb_keys.right.symbol).to eq('right')
      expect(hand_mapping.thumb_keys.right.keycode.to_s).to eq('Alt')
    end

    it 'handles nil YAML hash' do
      hand_mapping = described_class.from_yaml_hash(hand: :left, yaml_hand: nil, position_map: position_map)

      expect(hand_mapping.hand).to eq(:left)
      expect(hand_mapping.row0).to eq([])
      expect(hand_mapping.thumb_keys).to be_a(Cornix::Models::Layer::ThumbKeys)
    end

    it 'sets correct logical coordinates' do
      yaml_hand = {
        'row0' => { 'Q' => 'Tab' },
        'thumb_keys' => { 'left' => 'Space' }
      }

      hand_mapping = described_class.from_yaml_hash(hand: :left, yaml_hand: yaml_hand, position_map: position_map)

      expect(hand_mapping.row0[0].logical_coord[:hand]).to eq(:left)
      expect(hand_mapping.row0[0].logical_coord[:row]).to eq(0)
      expect(hand_mapping.row0[0].logical_coord[:col]).to eq(1)
      expect(hand_mapping.thumb_keys.left.logical_coord[:hand]).to eq(:left)
      expect(hand_mapping.thumb_keys.left.logical_coord[:row]).to eq(3)
      expect(hand_mapping.thumb_keys.left.logical_coord[:col]).to eq(3)
    end
  end

  describe '#to_yaml_hash' do
    it 'converts HandMapping to YAML hash' do
      key1 = Cornix::Models::Layer::KeyMapping.new(symbol: 'Q', keycode: 'Tab', logical_coord: { hand: :left, row: 0, col: 1 })
      key2 = Cornix::Models::Layer::KeyMapping.new(symbol: 'W', keycode: 'Space', logical_coord: { hand: :left, row: 0, col: 2 })
      thumb_key = Cornix::Models::Layer::KeyMapping.new(symbol: 'left', keycode: 'Ctrl', logical_coord: { hand: :left, row: 3, col: 3 })
      thumb_keys = Cornix::Models::Layer::ThumbKeys.new(left: thumb_key)

      hand_mapping = described_class.new(
        hand: :left,
        row0: [key1, key2],
        row1: [],
        row2: [],
        row3: [],
        thumb_keys: thumb_keys
      )

      yaml_hash = hand_mapping.to_yaml_hash

      expect(yaml_hash['row0']).to eq({ 'Q' => 'Tab', 'W' => 'Space' })
      expect(yaml_hash['row1']).to eq({})
      expect(yaml_hash['thumb_keys']).to eq({ 'left' => 'Ctrl' })
    end
  end

  describe 'round-trip YAML' do
    it 'maintains data through YAML round-trip' do
      yaml_hand = {
        'row0' => { 'Q' => 'Tab', 'W' => 'Space' },
        'row1' => { 'A' => 'Enter' },
        'row2' => {},
        'row3' => {},
        'thumb_keys' => { 'left' => 'Ctrl' }
      }

      hand_mapping = described_class.from_yaml_hash(hand: :left, yaml_hand: yaml_hand, position_map: position_map)
      restored_yaml = hand_mapping.to_yaml_hash

      expect(restored_yaml['row0']).to eq({ 'Q' => 'Tab', 'W' => 'Space' })
      expect(restored_yaml['row1']).to eq({ 'A' => 'Enter' })
      expect(restored_yaml['thumb_keys']).to eq({ 'left' => 'Ctrl' })
    end
  end

  # QMK round-trip テストは PositionMap の物理座標変換ロジックに依存するため、
  # ここでは簡易的なテストのみ実施
  describe '#to_qmk' do
    it 'returns 4x7 layout array' do
      hand_mapping = described_class.empty(:left)
      layout = hand_mapping.to_qmk(
        position_map: position_map,
        keycode_converter: keycode_converter,
        reference_converter: reference_converter
      )

      expect(layout.size).to eq(4)
      expect(layout[0].size).to eq(7)
    end

    it 'initializes all elements to -1' do
      hand_mapping = described_class.empty(:left)
      layout = hand_mapping.to_qmk(
        position_map: position_map,
        keycode_converter: keycode_converter
      )

      layout.each do |row|
        expect(row.all? { |v| v == -1 }).to be true
      end
    end
  end

  describe 'validation' do
    let(:key1) do
      Cornix::Models::Layer::KeyMapping.new(
        symbol: 'Q',
        keycode: 'Tab',
        logical_coord: { hand: :left, row: 0, col: 0 }
      )
    end

    let(:key2) do
      Cornix::Models::Layer::KeyMapping.new(
        symbol: 'W',
        keycode: 'Space',
        logical_coord: { hand: :left, row: 1, col: 0 }
      )
    end

    let(:key3) do
      Cornix::Models::Layer::KeyMapping.new(
        symbol: 'E',
        keycode: 'Enter',
        logical_coord: { hand: :left, row: 2, col: 0 }
      )
    end

    let(:thumb_keys) { Cornix::Models::Layer::ThumbKeys.new }

    let(:valid_hand_mapping) do
      described_class.new(
        hand: :left,
        row0: [key1],
        row1: [key2],
        row2: [key3],
        row3: [],
        thumb_keys: thumb_keys
      )
    end

    describe '#structurally_valid?' do
      it 'returns true for valid HandMapping' do
        expect(valid_hand_mapping.structurally_valid?).to be true
      end

      it 'returns false when hand is invalid' do
        invalid_hand = described_class.new(
          hand: :center,
          row0: [key1],
          row1: [],
          row2: [],
          row3: [],
          thumb_keys: thumb_keys
        )
        expect(invalid_hand.structurally_valid?).to be false
      end

      it 'validates row sizes' do
        # row0 に7要素（最大6）
        large_row = [key1, key2, key3, key1, key2, key3, key1]
        invalid_size = described_class.new(
          hand: :left,
          row0: large_row,
          row1: [],
          row2: [],
          row3: [],
          thumb_keys: thumb_keys
        )
        expect(invalid_size.structurally_valid?).to be false
      end

      it 'detects errors in keys' do
        invalid_key = Cornix::Models::Layer::KeyMapping.new(
          symbol: '',
          keycode: 'Tab',
          logical_coord: { hand: :left, row: 0, col: 0 }
        )
        invalid_keys = described_class.new(
          hand: :left,
          row0: [invalid_key],
          row1: [],
          row2: [],
          row3: [],
          thumb_keys: thumb_keys
        )
        expect(invalid_keys.structurally_valid?).to be false
      end

      it 'detects errors in thumb_keys' do
        invalid_thumb_key = Cornix::Models::Layer::KeyMapping.new(
          symbol: '',
          keycode: 'Tab',
          logical_coord: { hand: :left, row: 3, col: 3 }
        )
        invalid_thumbs = Cornix::Models::Layer::ThumbKeys.new(left: invalid_thumb_key)
        invalid = described_class.new(
          hand: :left,
          row0: [key1],
          row1: [],
          row2: [],
          row3: [],
          thumb_keys: invalid_thumbs
        )
        expect(invalid.structurally_valid?).to be false
      end
    end

    describe '#structural_errors' do
      it 'returns empty array for valid HandMapping' do
        expect(valid_hand_mapping.structural_errors).to be_empty
      end

      it 'includes error for invalid hand' do
        invalid_hand = described_class.new(
          hand: :center,
          row0: [],
          row1: [],
          row2: [],
          row3: [],
          thumb_keys: thumb_keys
        )
        errors = invalid_hand.structural_errors
        expect(errors.size).to be > 0
        expect(errors.join(' ')).to include('hand')
      end

      it 'includes errors from invalid keys' do
        invalid_key = Cornix::Models::Layer::KeyMapping.new(
          symbol: 'invalid!symbol',
          keycode: 'Tab',
          logical_coord: { hand: :left, row: 0, col: 0 }
        )
        invalid_keys = described_class.new(
          hand: :left,
          row0: [invalid_key],
          row1: [],
          row2: [],
          row3: [],
          thumb_keys: thumb_keys
        )
        errors = invalid_keys.structural_errors
        expect(errors.size).to be > 0
        expect(errors.join(' ')).to include('row0')
      end
    end

    describe '#validate!' do
      it 'does not raise for valid HandMapping', :skip do
        # TODO: Fix semantic validation issue with nested KeyMapping
        expect { valid_hand_mapping.validate! }.not_to raise_error
      end

      it 'raises ValidationError for invalid HandMapping' do
        invalid = described_class.new(
          hand: :invalid,
          row0: [],
          row1: [],
          row2: [],
          row3: [],
          thumb_keys: thumb_keys
        )
        expect { invalid.validate! }.to raise_error(Cornix::Models::Concerns::ValidationError)
      end
    end
  end
end
