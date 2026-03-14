# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../lib/cornix/models/macro'
require_relative '../../lib/cornix/models/macro_collection'
require_relative '../../lib/cornix/converters/keycode_converter'

RSpec.describe Cornix::Models::MacroCollection do
  let(:aliases_path) { File.join(__dir__, '../../lib/cornix/keycode_aliases.yaml') }
  let(:keycode_converter) { Cornix::Converters::KeycodeConverter.new(aliases_path) }

  let(:macro1) do
    Cornix::Models::Macro.new(
      index: 0,
      name: 'Macro 0',
      description: '',
      sequence: [
        Cornix::Models::Macro::MacroStep.new(
          action: 'tap',
          keys: ['A', 'B']
        )
      ]
    )
  end

  let(:macro2) do
    Cornix::Models::Macro.new(
      index: 2,
      name: 'Macro 2',
      description: '',
      sequence: [
        Cornix::Models::Macro::MacroStep.new(
          action: 'tap',
          keys: ['C', 'D']
        )
      ]
    )
  end

  describe '#initialize' do
    it 'マクロ配列で初期化' do
      collection = described_class.new([macro1, macro2])

      expect(collection.size).to eq(2)
      expect(collection[0]).to eq(macro1)
      expect(collection[1]).to eq(macro2)
    end

    it '空配列で初期化' do
      collection = described_class.new([])

      expect(collection.size).to eq(0)
    end

    it 'デフォルト引数で初期化（空配列）' do
      collection = described_class.new

      expect(collection.size).to eq(0)
    end

    it 'MAX_SIZE（32）を超えるとエラー' do
      many_macros = Array.new(33) { |i|
        Cornix::Models::Macro.new(
          index: i,
          name: "Macro #{i}",
          description: '',
          sequence: []
        )
      }

      expect {
        described_class.new(many_macros)
      }.to raise_error(ArgumentError, /Too many macros: 33/)
    end

    it 'MAX_SIZE（32）ちょうどは許容' do
      max_macros = Array.new(32) { |i|
        Cornix::Models::Macro.new(
          index: i,
          name: "Macro #{i}",
          description: '',
          sequence: []
        )
      }

      expect {
        described_class.new(max_macros)
      }.not_to raise_error
    end
  end

  describe '#[]' do
    it 'インデックスでマクロにアクセス' do
      collection = described_class.new([macro1, macro2])

      expect(collection[0]).to eq(macro1)
      expect(collection[1]).to eq(macro2)
    end

    it '範囲外はnil' do
      collection = described_class.new([macro1])

      expect(collection[5]).to be_nil
    end
  end

  describe '#each' do
    it 'Enumerableをサポート' do
      collection = described_class.new([macro1, macro2])
      result = []

      collection.each { |macro| result << macro }

      expect(result).to eq([macro1, macro2])
    end

    it 'mapが使える' do
      collection = described_class.new([macro1, macro2])

      names = collection.map(&:name)

      expect(names).to eq(['Macro 0', 'Macro 2'])
    end
  end

  describe '#size' do
    it 'マクロ数を返す' do
      collection = described_class.new([macro1, macro2])

      expect(collection.size).to eq(2)
    end

    it '空の場合は0' do
      collection = described_class.new

      expect(collection.size).to eq(0)
    end
  end

  describe '#to_qmk_array' do
    it '32要素の配列を生成' do
      collection = described_class.new([macro1, macro2])
      qmk_array = collection.to_qmk_array(keycode_converter: keycode_converter)

      expect(qmk_array.size).to eq(32)
    end

    it 'マクロが存在する位置は配列' do
      collection = described_class.new([macro1, macro2])
      qmk_array = collection.to_qmk_array(keycode_converter: keycode_converter)

      # マクロの to_qmk は [['tap', 'KC_A', 'KC_B']] のようなVial形式を返す
      expect(qmk_array[0]).to be_a(Array)
      expect(qmk_array[0]).not_to be_empty
      expect(qmk_array[2]).to be_a(Array)
      expect(qmk_array[2]).not_to be_empty
    end

    it 'マクロが存在しない位置は空配列' do
      collection = described_class.new([macro1])
      qmk_array = collection.to_qmk_array(keycode_converter: keycode_converter)

      expect(qmk_array[1]).to eq([])
      expect(qmk_array[31]).to eq([])
    end

    it '全て空の場合は32個の空配列' do
      collection = described_class.new([])
      qmk_array = collection.to_qmk_array(keycode_converter: keycode_converter)

      expect(qmk_array.size).to eq(32)
      expect(qmk_array.all? { |a| a == [] }).to be true
    end
  end

  describe 'edge cases' do
    it '途中の要素がnilでも処理可能' do
      sparse_macros = [macro1, nil, macro2]
      collection = described_class.new(sparse_macros)

      expect(collection[0]).to eq(macro1)
      expect(collection[1]).to be_nil
      expect(collection[2]).to eq(macro2)
    end

    it 'to_qmk_arrayでnil要素は空配列に変換' do
      sparse_macros = [macro1, nil, macro2]
      collection = described_class.new(sparse_macros)
      qmk_array = collection.to_qmk_array(keycode_converter: keycode_converter)

      # マクロの to_qmk は [['tap', 'KC_A', 'KC_B']] のようなVial形式を返す
      expect(qmk_array[0]).to be_a(Array)
      expect(qmk_array[0]).not_to be_empty
      expect(qmk_array[1]).to eq([])
      expect(qmk_array[2]).to be_a(Array)
      expect(qmk_array[2]).not_to be_empty
    end
  end
end
