# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../lib/cornix/models/combo'
require_relative '../../lib/cornix/models/combo_collection'

RSpec.describe Cornix::Models::ComboCollection do
  let(:combo1) do
    Cornix::Models::Combo.new(
      index: 0,
      name: 'Combo 0',
      description: '',
      trigger_keys: [20, 8],
      output_key: 47
    )
  end

  let(:combo2) do
    Cornix::Models::Combo.new(
      index: 2,
      name: 'Combo 2',
      description: '',
      trigger_keys: [20, 21],
      output_key: 48
    )
  end

  describe '#initialize' do
    it 'コンボ配列で初期化' do
      collection = described_class.new([combo1, combo2])

      expect(collection.size).to eq(2)
      expect(collection[0]).to eq(combo1)
      expect(collection[1]).to eq(combo2)
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
      many_combos = Array.new(33) { |i|
        Cornix::Models::Combo.new(
          index: i,
          name: "Combo #{i}",
          description: '',
          trigger_keys: [],
          output_key: 0
        )
      }

      expect {
        described_class.new(many_combos)
      }.to raise_error(ArgumentError, /Too many combos: 33/)
    end

    it 'MAX_SIZE（32）ちょうどは許容' do
      max_combos = Array.new(32) { |i|
        Cornix::Models::Combo.new(
          index: i,
          name: "Combo #{i}",
          description: '',
          trigger_keys: [],
          output_key: 0
        )
      }

      expect {
        described_class.new(max_combos)
      }.not_to raise_error
    end
  end

  describe '#[]' do
    it 'インデックスでコンボにアクセス' do
      collection = described_class.new([combo1, combo2])

      expect(collection[0]).to eq(combo1)
      expect(collection[1]).to eq(combo2)
    end

    it '範囲外はnil' do
      collection = described_class.new([combo1])

      expect(collection[5]).to be_nil
    end
  end

  describe '#each' do
    it 'Enumerableをサポート' do
      collection = described_class.new([combo1, combo2])
      result = []

      collection.each { |combo| result << combo }

      expect(result).to eq([combo1, combo2])
    end

    it 'mapが使える' do
      collection = described_class.new([combo1, combo2])

      names = collection.map(&:name)

      expect(names).to eq(['Combo 0', 'Combo 2'])
    end
  end

  describe '#size' do
    it 'コンボ数を返す' do
      collection = described_class.new([combo1, combo2])

      expect(collection.size).to eq(2)
    end

    it '空の場合は0' do
      collection = described_class.new

      expect(collection.size).to eq(0)
    end
  end

  describe '#to_qmk_array' do
    it '32要素の配列を生成' do
      collection = described_class.new([combo1, combo2])
      qmk_array = collection.to_qmk_array

      expect(qmk_array.size).to eq(32)
    end

    it 'コンボが存在する位置は配列[5要素]（空スロットはKC_NO）' do
      collection = described_class.new([combo1, combo2])
      qmk_array = collection.to_qmk_array

      expect(qmk_array[0]).to eq([20, 8, 'KC_NO', 'KC_NO', 47])
      expect(qmk_array[2]).to eq([20, 21, 'KC_NO', 'KC_NO', 48])
    end

    it 'コンボが存在しない位置は["KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO"]' do
      collection = described_class.new([combo1])
      qmk_array = collection.to_qmk_array

      expect(qmk_array[1]).to eq(['KC_NO', 'KC_NO', 'KC_NO', 'KC_NO', 'KC_NO'])
      expect(qmk_array[31]).to eq(['KC_NO', 'KC_NO', 'KC_NO', 'KC_NO', 'KC_NO'])
    end

    it '全て空の場合は32個の["KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO"]' do
      collection = described_class.new([])
      qmk_array = collection.to_qmk_array

      expect(qmk_array.size).to eq(32)
      expect(qmk_array.all? { |a| a == ['KC_NO', 'KC_NO', 'KC_NO', 'KC_NO', 'KC_NO'] }).to be true
    end
  end

  describe 'edge cases' do
    it '途中の要素がnilでも処理可能' do
      sparse_combos = [combo1, nil, combo2]
      collection = described_class.new(sparse_combos)

      expect(collection[0]).to eq(combo1)
      expect(collection[1]).to be_nil
      expect(collection[2]).to eq(combo2)
    end

    it 'to_qmk_arrayでnil要素は["KC_NO", "KC_NO", "KC_NO", "KC_NO", "KC_NO"]に変換' do
      sparse_combos = [combo1, nil, combo2]
      collection = described_class.new(sparse_combos)
      qmk_array = collection.to_qmk_array

      expect(qmk_array[0]).to eq([20, 8, 'KC_NO', 'KC_NO', 47])
      expect(qmk_array[1]).to eq(['KC_NO', 'KC_NO', 'KC_NO', 'KC_NO', 'KC_NO'])
      expect(qmk_array[2]).to eq([20, 21, 'KC_NO', 'KC_NO', 48])
    end
  end
end
