# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../lib/cornix/models/tap_dance'
require_relative '../../lib/cornix/models/tap_dance_collection'

RSpec.describe Cornix::Models::TapDanceCollection do
  let(:tap_dance1) do
    Cornix::Models::TapDance.new(
      index: 0,
      name: 'TapDance 0',
      description: '',
      on_tap: 41,
      on_hold: 1,
      on_double_tap: 41,
      on_tap_hold: 1,
      tapping_term: 200
    )
  end

  let(:tap_dance2) do
    Cornix::Models::TapDance.new(
      index: 2,
      name: 'TapDance 2',
      description: '',
      on_tap: 42,
      on_hold: 2,
      on_double_tap: 42,
      on_tap_hold: 2,
      tapping_term: 250
    )
  end

  describe '#initialize' do
    it 'タップダンス配列で初期化' do
      collection = described_class.new([tap_dance1, tap_dance2])

      expect(collection.size).to eq(2)
      expect(collection[0]).to eq(tap_dance1)
      expect(collection[1]).to eq(tap_dance2)
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
      many_tap_dances = Array.new(33) { |i|
        Cornix::Models::TapDance.new(
          index: i,
          name: "TapDance #{i}",
          description: '',
          on_tap: 0,
          on_hold: 0,
          on_double_tap: 0,
          on_tap_hold: 0,
          tapping_term: 0
        )
      }

      expect {
        described_class.new(many_tap_dances)
      }.to raise_error(ArgumentError, /Too many tap dances: 33/)
    end

    it 'MAX_SIZE（32）ちょうどは許容' do
      max_tap_dances = Array.new(32) { |i|
        Cornix::Models::TapDance.new(
          index: i,
          name: "TapDance #{i}",
          description: '',
          on_tap: 0,
          on_hold: 0,
          on_double_tap: 0,
          on_tap_hold: 0,
          tapping_term: 0
        )
      }

      expect {
        described_class.new(max_tap_dances)
      }.not_to raise_error
    end
  end

  describe '#[]' do
    it 'インデックスでタップダンスにアクセス' do
      collection = described_class.new([tap_dance1, tap_dance2])

      expect(collection[0]).to eq(tap_dance1)
      expect(collection[1]).to eq(tap_dance2)
    end

    it '範囲外はnil' do
      collection = described_class.new([tap_dance1])

      expect(collection[5]).to be_nil
    end
  end

  describe '#each' do
    it 'Enumerableをサポート' do
      collection = described_class.new([tap_dance1, tap_dance2])
      result = []

      collection.each { |tap_dance| result << tap_dance }

      expect(result).to eq([tap_dance1, tap_dance2])
    end

    it 'mapが使える' do
      collection = described_class.new([tap_dance1, tap_dance2])

      names = collection.map(&:name)

      expect(names).to eq(['TapDance 0', 'TapDance 2'])
    end
  end

  describe '#size' do
    it 'タップダンス数を返す' do
      collection = described_class.new([tap_dance1, tap_dance2])

      expect(collection.size).to eq(2)
    end

    it '空の場合は0' do
      collection = described_class.new

      expect(collection.size).to eq(0)
    end
  end

  describe '#to_qmk_array' do
    it '32要素の配列を生成' do
      collection = described_class.new([tap_dance1, tap_dance2])
      qmk_array = collection.to_qmk_array

      expect(qmk_array.size).to eq(32)
    end

    it 'タップダンスが存在する位置は配列[5要素]' do
      collection = described_class.new([tap_dance1, tap_dance2])
      qmk_array = collection.to_qmk_array

      expect(qmk_array[0]).to eq([41, 1, 41, 1, 200])
      expect(qmk_array[2]).to eq([42, 2, 42, 2, 250])
    end

    it 'タップダンスが存在しない位置は["KC_NO", "KC_NO", "KC_NO", "KC_NO", 250]' do
      collection = described_class.new([tap_dance1])
      qmk_array = collection.to_qmk_array

      expect(qmk_array[1]).to eq(['KC_NO', 'KC_NO', 'KC_NO', 'KC_NO', 250])
      expect(qmk_array[31]).to eq(['KC_NO', 'KC_NO', 'KC_NO', 'KC_NO', 250])
    end

    it '全て空の場合は32個の["KC_NO", "KC_NO", "KC_NO", "KC_NO", 250]' do
      collection = described_class.new([])
      qmk_array = collection.to_qmk_array

      expect(qmk_array.size).to eq(32)
      expect(qmk_array.all? { |a| a == ['KC_NO', 'KC_NO', 'KC_NO', 'KC_NO', 250] }).to be true
    end
  end

  describe 'edge cases' do
    it '途中の要素がnilでも処理可能' do
      sparse_tap_dances = [tap_dance1, nil, tap_dance2]
      collection = described_class.new(sparse_tap_dances)

      expect(collection[0]).to eq(tap_dance1)
      expect(collection[1]).to be_nil
      expect(collection[2]).to eq(tap_dance2)
    end

    it 'to_qmk_arrayでnil要素は["KC_NO", "KC_NO", "KC_NO", "KC_NO", 250]に変換' do
      sparse_tap_dances = [tap_dance1, nil, tap_dance2]
      collection = described_class.new(sparse_tap_dances)
      qmk_array = collection.to_qmk_array

      expect(qmk_array[0]).to eq([41, 1, 41, 1, 200])
      expect(qmk_array[1]).to eq(['KC_NO', 'KC_NO', 'KC_NO', 'KC_NO', 250])
      expect(qmk_array[2]).to eq([42, 2, 42, 2, 250])
    end
  end
end
