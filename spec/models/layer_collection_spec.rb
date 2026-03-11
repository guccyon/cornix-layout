# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../lib/cornix/models/layer'
require_relative '../../lib/cornix/models/layer_collection'
require_relative '../../lib/cornix/position_map'
require_relative '../../lib/cornix/converters/keycode_converter'

RSpec.describe Cornix::Models::LayerCollection do
  let(:position_map) do
    position_map_path = File.join(__dir__, '../../lib/cornix/position_map.yaml')
    Cornix::PositionMap.new(position_map_path)
  end

  let(:keycode_converter) do
    aliases_path = File.join(__dir__, '../../lib/cornix/keycode_aliases.yaml')
    Cornix::Converters::KeycodeConverter.new(aliases_path)
  end

  let(:layer1) do
    Cornix::Models::Layer.new(
      name: 'Layer 0',
      description: '',
      index: 0,
      left_hand: Cornix::Models::Layer::HandMapping.empty(:left),
      right_hand: Cornix::Models::Layer::HandMapping.empty(:right),
      encoders: Cornix::Models::Layer::EncoderMapping.new(
        left: { push: 'KC_MUTE', ccw: 'KC_VOLD', cw: 'KC_VOLU' },
        right: { push: 'KC_MUTE', ccw: 'KC_VOLD', cw: 'KC_VOLU' }
      )
    )
  end

  let(:layer2) do
    Cornix::Models::Layer.new(
      name: 'Layer 1',
      description: '',
      index: 1,
      left_hand: Cornix::Models::Layer::HandMapping.empty(:left),
      right_hand: Cornix::Models::Layer::HandMapping.empty(:right),
      encoders: Cornix::Models::Layer::EncoderMapping.new(
        left: { push: 'KC_MUTE', ccw: 'KC_VOLD', cw: 'KC_VOLU' },
        right: { push: 'KC_MUTE', ccw: 'KC_VOLD', cw: 'KC_VOLU' }
      )
    )
  end

  describe '#initialize' do
    it 'レイヤー配列で初期化' do
      collection = described_class.new([layer1, layer2])

      expect(collection.size).to eq(2)
      expect(collection[0]).to eq(layer1)
      expect(collection[1]).to eq(layer2)
    end

    it '空配列で初期化' do
      collection = described_class.new([])

      expect(collection.size).to eq(0)
    end

    it 'デフォルト引数で初期化（空配列）' do
      collection = described_class.new

      expect(collection.size).to eq(0)
    end

    it 'MAX_SIZE（10）を超えるとエラー' do
      many_layers = Array.new(11) { |i|
        Cornix::Models::Layer.new(
          name: "Layer #{i}",
          description: '',
          index: i,
          left_hand: Cornix::Models::Layer::HandMapping.empty(:left),
          right_hand: Cornix::Models::Layer::HandMapping.empty(:right),
          encoders: Cornix::Models::Layer::EncoderMapping.new(left: {}, right: {})
        )
      }

      expect {
        described_class.new(many_layers)
      }.to raise_error(ArgumentError, /Too many layers: 11/)
    end

    it 'MAX_SIZE（10）ちょうどは許容' do
      max_layers = Array.new(10) { |i|
        Cornix::Models::Layer.new(
          name: "Layer #{i}",
          description: '',
          index: i,
          left_hand: Cornix::Models::Layer::HandMapping.empty(:left),
          right_hand: Cornix::Models::Layer::HandMapping.empty(:right),
          encoders: Cornix::Models::Layer::EncoderMapping.new(left: {}, right: {})
        )
      }

      expect {
        described_class.new(max_layers)
      }.not_to raise_error
    end
  end

  describe '#[]' do
    it 'インデックスでレイヤーにアクセス' do
      collection = described_class.new([layer1, layer2])

      expect(collection[0]).to eq(layer1)
      expect(collection[1]).to eq(layer2)
    end

    it '範囲外はnil' do
      collection = described_class.new([layer1])

      expect(collection[5]).to be_nil
    end
  end

  describe '#each' do
    it 'Enumerableをサポート' do
      collection = described_class.new([layer1, layer2])
      result = []

      collection.each { |layer| result << layer }

      expect(result).to eq([layer1, layer2])
    end

    it 'mapが使える' do
      collection = described_class.new([layer1, layer2])

      names = collection.map(&:name)

      expect(names).to eq(['Layer 0', 'Layer 1'])
    end
  end

  describe '#size' do
    it 'レイヤー数を返す' do
      collection = described_class.new([layer1, layer2])

      expect(collection.size).to eq(2)
    end

    it '空の場合は0' do
      collection = described_class.new

      expect(collection.size).to eq(0)
    end
  end

  describe '#to_qmk_layout_array' do
    it '10要素の配列を生成' do
      collection = described_class.new([layer1, layer2])
      qmk_array = collection.to_qmk_layout_array(position_map: position_map, keycode_converter: keycode_converter, reference_converter: nil)

      expect(qmk_array.size).to eq(10)
    end

    it 'レイヤーが存在する位置は8×7の配列' do
      collection = described_class.new([layer1, layer2])
      qmk_array = collection.to_qmk_layout_array(position_map: position_map, keycode_converter: keycode_converter, reference_converter: nil)

      expect(qmk_array[0].size).to eq(8)
      expect(qmk_array[0][0].size).to eq(7)
      expect(qmk_array[1].size).to eq(8)
    end

    it 'レイヤーが存在しない位置は-1で埋められた8×7配列' do
      collection = described_class.new([layer1])
      qmk_array = collection.to_qmk_layout_array(position_map: position_map, keycode_converter: keycode_converter, reference_converter: nil)

      expect(qmk_array[1].all? { |row| row.all? { |v| v == -1 } }).to be true
      expect(qmk_array[9].all? { |row| row.all? { |v| v == -1 } }).to be true
    end

    it '全て空の場合は10個の空レイヤー' do
      collection = described_class.new([])
      qmk_array = collection.to_qmk_layout_array(position_map: position_map, keycode_converter: keycode_converter, reference_converter: nil)

      expect(qmk_array.size).to eq(10)
      expect(qmk_array.all? { |layout| layout.all? { |row| row.all? { |v| v == -1 } } }).to be true
    end
  end

  describe '#to_qmk_encoder_array' do
    it '10要素の配列を生成' do
      collection = described_class.new([layer1, layer2])
      qmk_array = collection.to_qmk_encoder_array(position_map: position_map, keycode_converter: keycode_converter, reference_converter: nil)

      expect(qmk_array.size).to eq(10)
    end

    it 'レイヤーが存在する位置は2×2の配列' do
      collection = described_class.new([layer1, layer2])
      qmk_array = collection.to_qmk_encoder_array(position_map: position_map, keycode_converter: keycode_converter, reference_converter: nil)

      expect(qmk_array[0].size).to eq(2)
      expect(qmk_array[0][0].size).to eq(2)
    end

    it 'レイヤーが存在しない位置は-1で埋められた2×2配列' do
      collection = described_class.new([layer1])
      qmk_array = collection.to_qmk_encoder_array(position_map: position_map, keycode_converter: keycode_converter, reference_converter: nil)

      expect(qmk_array[1].all? { |row| row.all? { |v| v == -1 } }).to be true
      expect(qmk_array[9].all? { |row| row.all? { |v| v == -1 } }).to be true
    end
  end

  describe 'edge cases' do
    it '途中の要素がnilでも処理可能' do
      sparse_layers = [layer1, nil, layer2]
      collection = described_class.new(sparse_layers)

      expect(collection[0]).to eq(layer1)
      expect(collection[1]).to be_nil
      expect(collection[2]).to eq(layer2)
    end

    it 'to_qmk_layout_arrayでnil要素は空レイヤーに変換' do
      sparse_layers = [layer1, nil, layer2]
      collection = described_class.new(sparse_layers)
      qmk_array = collection.to_qmk_layout_array(position_map: position_map, keycode_converter: keycode_converter, reference_converter: nil)

      expect(qmk_array[1].all? { |row| row.all? { |v| v == -1 } }).to be true
    end
  end
end
