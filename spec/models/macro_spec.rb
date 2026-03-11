# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../lib/cornix/models/macro'

RSpec.describe Cornix::Models::Macro do
  let(:sample_sequence) { [1, 2, 3, 4, 0] }

  describe '.from_qmk' do
    it 'QMK配列からMacroを生成' do
      macro = described_class.from_qmk(3, sample_sequence)

      expect(macro.index).to eq(3)
      expect(macro.name).to eq('Macro 3')
      expect(macro.description).to eq('')
      expect(macro.sequence).to eq(sample_sequence)
    end

    it '空配列を許容' do
      macro = described_class.from_qmk(0, [])

      expect(macro.sequence).to eq([])
      expect(macro.empty?).to be true
    end
  end

  describe '#to_qmk' do
    it 'MacroをQMK配列に変換' do
      macro = described_class.from_qmk(3, sample_sequence)
      qmk_array = macro.to_qmk

      expect(qmk_array).to eq(sample_sequence)
    end

    it '空配列を返す' do
      macro = described_class.from_qmk(0, [])
      qmk_array = macro.to_qmk

      expect(qmk_array).to eq([])
    end
  end

  describe '.from_yaml_hash' do
    let(:yaml_hash) do
      {
        'index' => 5,
        'name' => 'End of Line',
        'description' => 'Jump to end of line',
        'sequence' => sample_sequence
      }
    end

    it 'YAML HashからMacroを生成' do
      macro = described_class.from_yaml_hash(yaml_hash)

      expect(macro.index).to eq(5)
      expect(macro.name).to eq('End of Line')
      expect(macro.description).to eq('Jump to end of line')
      expect(macro.sequence).to eq(sample_sequence)
    end

    it 'descriptionがnilの場合は空文字列' do
      yaml_hash_no_desc = yaml_hash.dup
      yaml_hash_no_desc.delete('description')

      macro = described_class.from_yaml_hash(yaml_hash_no_desc)

      expect(macro.description).to eq('')
    end
  end

  describe '#to_yaml_hash' do
    it 'MacroをYAML Hashに変換' do
      macro = described_class.new(
        index: 5,
        name: 'End of Line',
        description: 'Jump to end of line',
        sequence: sample_sequence
      )
      yaml_hash = macro.to_yaml_hash

      expect(yaml_hash['index']).to eq(5)
      expect(yaml_hash['name']).to eq('End of Line')
      expect(yaml_hash['description']).to eq('Jump to end of line')
      expect(yaml_hash['sequence']).to eq(sample_sequence)
    end
  end

  describe '#empty?' do
    it '空配列の場合はtrue' do
      macro = described_class.new(
        index: 0,
        name: 'Empty',
        description: '',
        sequence: []
      )

      expect(macro.empty?).to be true
    end

    it 'nilの場合はtrue' do
      macro = described_class.new(
        index: 0,
        name: 'Nil',
        description: '',
        sequence: nil
      )

      expect(macro.empty?).to be true
    end

    it 'シーケンスがある場合はfalse' do
      macro = described_class.new(
        index: 0,
        name: 'Non-empty',
        description: '',
        sequence: [1, 2, 3]
      )

      expect(macro.empty?).to be false
    end
  end

  describe 'round-trip conversion' do
    it 'QMK → Macro → QMK の往復変換' do
      original_array = [10, 20, 30, 0]
      macro = described_class.from_qmk(7, original_array)
      qmk_array = macro.to_qmk

      expect(qmk_array).to eq(original_array)
    end

    it 'YAML → Macro → YAML の往復変換' do
      original_hash = {
        'index' => 8,
        'name' => 'Test Macro',
        'description' => 'Test description',
        'sequence' => [5, 6, 7, 8, 0]
      }
      macro = described_class.from_yaml_hash(original_hash)
      yaml_hash = macro.to_yaml_hash

      expect(yaml_hash).to eq(original_hash)
    end
  end

  describe 'edge cases' do
    it '大きなシーケンスを許容' do
      large_sequence = Array.new(100) { |i| i }
      macro = described_class.new(
        index: 0,
        name: 'Large',
        description: '',
        sequence: large_sequence
      )

      expect(macro.sequence.size).to eq(100)
      expect(macro.to_qmk).to eq(large_sequence)
    end

    it '空文字列の名前を許容' do
      macro = described_class.new(
        index: 0,
        name: '',
        description: '',
        sequence: []
      )

      expect(macro.name).to eq('')
    end
  end
end
