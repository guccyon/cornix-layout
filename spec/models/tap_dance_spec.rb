# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../lib/cornix/models/tap_dance'

RSpec.describe Cornix::Models::TapDance do
  let(:sample_qmk_array) { [41, 1, 41, 1, 200] } # on_tap: KC_ESC, on_hold: MO(1), etc.

  describe '.from_qmk' do
    it 'QMK配列からTapDanceを生成' do
      tap_dance = described_class.from_qmk(3, sample_qmk_array)

      expect(tap_dance.index).to eq(3)
      expect(tap_dance.name).to eq('TapDance 3')
      expect(tap_dance.description).to eq('')
      expect(tap_dance.on_tap).to eq(41)
      expect(tap_dance.on_hold).to eq(1)
      expect(tap_dance.on_double_tap).to eq(41)
      expect(tap_dance.on_tap_hold).to eq(1)
      expect(tap_dance.tapping_term).to eq(200)
    end

    it '空配列（全ゼロ）を許容' do
      tap_dance = described_class.from_qmk(0, [0, 0, 0, 0, 0])

      expect(tap_dance.on_tap).to eq(0)
      expect(tap_dance.on_hold).to eq(0)
      expect(tap_dance.on_double_tap).to eq(0)
      expect(tap_dance.on_tap_hold).to eq(0)
      expect(tap_dance.tapping_term).to eq(0)
      expect(tap_dance.empty?).to be true
    end
  end

  describe '#to_qmk' do
    it 'TapDanceをQMK配列に変換' do
      tap_dance = described_class.from_qmk(3, sample_qmk_array)
      qmk_array = tap_dance.to_qmk

      expect(qmk_array).to eq(sample_qmk_array)
    end

    it 'ゼロ配列を返す' do
      tap_dance = described_class.from_qmk(0, [0, 0, 0, 0, 0])
      qmk_array = tap_dance.to_qmk

      expect(qmk_array).to eq([0, 0, 0, 0, 0])
    end
  end

  describe '.from_yaml_hash' do
    let(:yaml_hash) do
      {
        'index' => 5,
        'name' => 'Escape or Layer',
        'description' => 'Tap for Escape, Hold for Layer 1',
        'on_tap' => 41,
        'on_hold' => 1,
        'on_double_tap' => 41,
        'on_tap_hold' => 1,
        'tapping_term' => 200
      }
    end

    it 'YAML HashからTapDanceを生成' do
      tap_dance = described_class.from_yaml_hash(yaml_hash)

      expect(tap_dance.index).to eq(5)
      expect(tap_dance.name).to eq('Escape or Layer')
      expect(tap_dance.description).to eq('Tap for Escape, Hold for Layer 1')
      expect(tap_dance.on_tap).to eq(41)
      expect(tap_dance.on_hold).to eq(1)
      expect(tap_dance.on_double_tap).to eq(41)
      expect(tap_dance.on_tap_hold).to eq(1)
      expect(tap_dance.tapping_term).to eq(200)
    end

    it 'descriptionがnilの場合は空文字列' do
      yaml_hash_no_desc = yaml_hash.dup
      yaml_hash_no_desc.delete('description')

      tap_dance = described_class.from_yaml_hash(yaml_hash_no_desc)

      expect(tap_dance.description).to eq('')
    end
  end

  describe '#to_yaml_hash' do
    it 'TapDanceをYAML Hashに変換' do
      tap_dance = described_class.new(
        index: 5,
        name: 'Escape or Layer',
        description: 'Tap for Escape, Hold for Layer 1',
        on_tap: 41,
        on_hold: 1,
        on_double_tap: 41,
        on_tap_hold: 1,
        tapping_term: 200
      )
      yaml_hash = tap_dance.to_yaml_hash

      expect(yaml_hash['index']).to eq(5)
      expect(yaml_hash['name']).to eq('Escape or Layer')
      expect(yaml_hash['description']).to eq('Tap for Escape, Hold for Layer 1')
      expect(yaml_hash['on_tap']).to eq(41)
      expect(yaml_hash['on_hold']).to eq(1)
      expect(yaml_hash['on_double_tap']).to eq(41)
      expect(yaml_hash['on_tap_hold']).to eq(1)
      expect(yaml_hash['tapping_term']).to eq(200)
    end
  end

  describe '#empty?' do
    it '全アクションがゼロの場合はtrue' do
      tap_dance = described_class.new(
        index: 0,
        name: 'Empty',
        description: '',
        on_tap: 0,
        on_hold: 0,
        on_double_tap: 0,
        on_tap_hold: 0,
        tapping_term: 0
      )

      expect(tap_dance.empty?).to be true
    end

    it '全アクションがnilの場合はtrue' do
      tap_dance = described_class.new(
        index: 0,
        name: 'Nil',
        description: '',
        on_tap: nil,
        on_hold: nil,
        on_double_tap: nil,
        on_tap_hold: nil,
        tapping_term: 100
      )

      expect(tap_dance.empty?).to be true
    end

    it '1つでもアクションがある場合はfalse' do
      tap_dance = described_class.new(
        index: 0,
        name: 'Non-empty',
        description: '',
        on_tap: 41,
        on_hold: 0,
        on_double_tap: 0,
        on_tap_hold: 0,
        tapping_term: 200
      )

      expect(tap_dance.empty?).to be false
    end
  end

  describe 'round-trip conversion' do
    it 'QMK → TapDance → QMK の往復変換' do
      original_array = [41, 1, 41, 1, 200]
      tap_dance = described_class.from_qmk(7, original_array)
      qmk_array = tap_dance.to_qmk

      expect(qmk_array).to eq(original_array)
    end

    it 'YAML → TapDance → YAML の往復変換' do
      original_hash = {
        'index' => 8,
        'name' => 'Test TapDance',
        'description' => 'Test description',
        'on_tap' => 41,
        'on_hold' => 1,
        'on_double_tap' => 41,
        'on_tap_hold' => 1,
        'tapping_term' => 200
      }
      tap_dance = described_class.from_yaml_hash(original_hash)
      yaml_hash = tap_dance.to_yaml_hash

      expect(yaml_hash).to eq(original_hash)
    end
  end

  describe 'edge cases' do
    it '大きな値を許容' do
      large_values = [65535, 65535, 65535, 65535, 10000]
      tap_dance = described_class.new(
        index: 0,
        name: 'Large',
        description: '',
        on_tap: large_values[0],
        on_hold: large_values[1],
        on_double_tap: large_values[2],
        on_tap_hold: large_values[3],
        tapping_term: large_values[4]
      )

      expect(tap_dance.to_qmk).to eq(large_values)
    end

    it '空文字列の名前を許容' do
      tap_dance = described_class.new(
        index: 0,
        name: '',
        description: '',
        on_tap: 0,
        on_hold: 0,
        on_double_tap: 0,
        on_tap_hold: 0,
        tapping_term: 0
      )

      expect(tap_dance.name).to eq('')
    end
  end
end
