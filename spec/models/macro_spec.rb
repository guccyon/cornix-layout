# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../lib/cornix/models/macro'
require_relative '../../lib/cornix/converters/keycode_converter'
require 'tempfile'
require 'yaml'

RSpec.describe Cornix::Models::Macro do
  let(:test_aliases) do
    {
      'aliases' => {
        'A' => 'KC_A',
        'B' => 'KC_B',
        'C' => 'KC_C',
        'LShift' => 'KC_LSHIFT',
        'Space' => 'KC_SPACE'
      }
    }
  end

  let(:yaml_file) do
    file = Tempfile.new(['keycode_aliases', '.yaml'])
    file.write(YAML.dump(test_aliases))
    file.close
    file
  end

  let(:keycode_converter) { Cornix::Converters::KeycodeConverter.new(yaml_file.path) }
  let(:context) { { keycode_converter: keycode_converter } }

  after do
    yaml_file.unlink
  end

  let(:sample_steps) do
    [
      Cornix::Models::Macro::MacroStep.new(action: 'tap', keys: ['A', 'B']),
      Cornix::Models::Macro::MacroStep.new(action: 'delay', duration: 250),
      Cornix::Models::Macro::MacroStep.new(action: 'tap', keys: ['C'])
    ]
  end

  describe '#initialize' do
    it 'マクロを初期化' do
      macro = described_class.new(
        index: 5,
        name: 'Test Macro',
        description: 'Test description',
        sequence: sample_steps
      )

      expect(macro.index).to eq(5)
      expect(macro.name).to eq('Test Macro')
      expect(macro.description).to eq('Test description')
      expect(macro.sequence).to eq(sample_steps)
    end
  end

  describe 'validation' do
    describe 'structural validations' do
      it 'indexが必須' do
        macro = described_class.new(
          index: nil,
          name: 'Test',
          description: '',
          sequence: sample_steps
        )
        errors = macro.structural_errors
        expect(errors).not_to be_empty
        expect(errors.join).to include('index: cannot be blank')
      end

      it 'indexが0-31の範囲内であること' do
        macro = described_class.new(
          index: 32,
          name: 'Test',
          description: '',
          sequence: sample_steps
        )
        errors = macro.structural_errors
        expect(errors).not_to be_empty
        expect(errors.join).to include('must be between 0 and 31')
      end

      it 'nameが必須' do
        macro = described_class.new(
          index: 0,
          name: nil,
          description: '',
          sequence: sample_steps
        )
        errors = macro.structural_errors
        expect(errors).not_to be_empty
        expect(errors.join).to include('name: cannot be blank')
      end

      it 'sequenceが必須' do
        macro = described_class.new(
          index: 0,
          name: 'Test',
          description: '',
          sequence: nil
        )
        errors = macro.structural_errors
        expect(errors).not_to be_empty
        expect(errors.join).to include('sequence: cannot be blank')
      end

      it 'sequenceが配列であること' do
        macro = described_class.new(
          index: 0,
          name: 'Test',
          description: '',
          sequence: 'not an array'
        )
        errors = macro.structural_errors
        expect(errors).not_to be_empty
        expect(errors.join).to include('sequence: must be a Array')
      end

      it 'sequenceの各要素がMacroStepであること' do
        macro = described_class.new(
          index: 0,
          name: 'Test',
          description: '',
          sequence: [sample_steps[0], 'invalid']
        )
        errors = macro.structural_errors
        expect(errors).not_to be_empty
        expect(errors.join).to include('contains non-MacroStep elements')
      end
    end

    describe 'semantic validations' do
      it '有効なマクロを検証' do
        macro = described_class.new(
          index: 0,
          name: 'Test',
          description: '',
          sequence: sample_steps
        )
        errors = macro.semantic_errors(context)
        expect(errors).to be_empty
      end

      it '無効なキーコードを含むマクロでエラー' do
        invalid_steps = [
          Cornix::Models::Macro::MacroStep.new(action: 'tap', keys: ['InvalidKey'])
        ]
        macro = described_class.new(
          index: 0,
          name: 'Test',
          description: '',
          sequence: invalid_steps
        )
        errors = macro.semantic_errors(context)
        expect(errors).not_to be_empty
        expect(errors.join).to include("Invalid keycode 'InvalidKey'")
      end
    end
  end

  describe '.from_qmk' do
    it 'QMK配列からMacroを生成' do
      qmk_array = [
        ['tap', 'KC_A', 'KC_B'],
        ['delay', 250],
        ['tap', 'KC_C']
      ]
      macro = described_class.from_qmk(3, qmk_array, keycode_converter: keycode_converter)

      expect(macro.index).to eq(3)
      expect(macro.name).to eq('Macro 3')
      expect(macro.description).to eq('')
      expect(macro.sequence.size).to eq(3)
      expect(macro.sequence[0].action).to eq('tap')
      expect(macro.sequence[0].keys).to eq(['A', 'B'])
      expect(macro.sequence[1].action).to eq('delay')
      expect(macro.sequence[1].duration).to eq(250)
      expect(macro.sequence[2].action).to eq('tap')
      expect(macro.sequence[2].keys).to eq(['C'])
    end

    it '空配列を許容' do
      macro = described_class.from_qmk(0, [], keycode_converter: keycode_converter)

      expect(macro.sequence).to eq([])
      expect(macro.empty?).to be true
    end
  end

  describe '#to_qmk' do
    it 'MacroをQMK配列に変換' do
      macro = described_class.new(
        index: 5,
        name: 'Test Macro',
        description: 'Test description',
        sequence: sample_steps
      )
      qmk_array = macro.to_qmk(keycode_converter: keycode_converter)

      expect(qmk_array).to eq([
        ['tap', 'KC_A', 'KC_B'],
        ['delay', 250],
        ['tap', 'KC_C']
      ])
    end

    it '空配列を返す' do
      macro = described_class.new(
        index: 0,
        name: 'Empty',
        description: '',
        sequence: []
      )
      qmk_array = macro.to_qmk(keycode_converter: keycode_converter)

      expect(qmk_array).to eq([])
    end
  end

  describe '.from_yaml_hash' do
    let(:yaml_hash) do
      {
        'index' => 5,
        'name' => 'End of Line',
        'description' => 'Jump to end of line',
        'sequence' => [
          { 'action' => 'tap', 'keys' => ['A', 'B'] },
          { 'action' => 'delay', 'duration' => 250 },
          { 'action' => 'beep' }
        ]
      }
    end

    it 'YAML HashからMacroを生成' do
      macro = described_class.from_yaml_hash(yaml_hash)

      expect(macro.index).to eq(5)
      expect(macro.name).to eq('End of Line')
      expect(macro.description).to eq('Jump to end of line')
      expect(macro.sequence.size).to eq(3)
      expect(macro.sequence[0].action).to eq('tap')
      expect(macro.sequence[0].keys).to eq(['A', 'B'])
      expect(macro.sequence[1].action).to eq('delay')
      expect(macro.sequence[1].duration).to eq(250)
      expect(macro.sequence[2].action).to eq('beep')
    end

    it 'descriptionがnilの場合は空文字列' do
      yaml_hash_no_desc = yaml_hash.dup
      yaml_hash_no_desc.delete('description')

      macro = described_class.from_yaml_hash(yaml_hash_no_desc)

      expect(macro.description).to eq('')
    end

    it '空のsequenceを許容' do
      yaml_hash_empty = yaml_hash.dup
      yaml_hash_empty['sequence'] = []

      macro = described_class.from_yaml_hash(yaml_hash_empty)

      expect(macro.sequence).to eq([])
    end
  end

  describe '#to_yaml_hash' do
    it 'MacroをYAML Hashに変換' do
      macro = described_class.new(
        index: 5,
        name: 'End of Line',
        description: 'Jump to end of line',
        sequence: sample_steps
      )
      yaml_hash = macro.to_yaml_hash

      expect(yaml_hash['index']).to eq(5)
      expect(yaml_hash['name']).to eq('End of Line')
      expect(yaml_hash['description']).to eq('Jump to end of line')
      expect(yaml_hash['sequence']).to eq([
        { 'action' => 'tap', 'keys' => ['A', 'B'] },
        { 'action' => 'delay', 'duration' => 250 },
        { 'action' => 'tap', 'keys' => ['C'] }
      ])
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
        sequence: sample_steps
      )

      expect(macro.empty?).to be false
    end
  end

  describe 'round-trip conversion' do
    it 'QMK → Macro → QMK の往復変換' do
      original_array = [
        ['tap', 'KC_A', 'KC_B'],
        ['delay', 100],
        ['beep']
      ]
      macro = described_class.from_qmk(7, original_array, keycode_converter: keycode_converter)
      qmk_array = macro.to_qmk(keycode_converter: keycode_converter)

      expect(qmk_array).to eq(original_array)
    end

    it 'YAML → Macro → YAML の往復変換' do
      original_hash = {
        'index' => 8,
        'name' => 'Test Macro',
        'description' => 'Test description',
        'sequence' => [
          { 'action' => 'tap', 'keys' => ['A'] },
          { 'action' => 'delay', 'duration' => 500 }
        ]
      }
      macro = described_class.from_yaml_hash(original_hash)
      yaml_hash = macro.to_yaml_hash

      expect(yaml_hash).to eq(original_hash)
    end
  end

  describe 'edge cases' do
    it '大きなシーケンスを許容' do
      large_sequence = Array.new(100) do |i|
        Cornix::Models::Macro::MacroStep.new(action: 'tap', keys: ['A'])
      end
      macro = described_class.new(
        index: 0,
        name: 'Large',
        description: '',
        sequence: large_sequence
      )

      expect(macro.sequence.size).to eq(100)
      qmk_array = macro.to_qmk(keycode_converter: keycode_converter)
      expect(qmk_array.size).to eq(100)
    end

    it '空文字列の名前を許容' do
      macro = described_class.new(
        index: 0,
        name: '',
        description: '',
        sequence: []
      )

      expect(macro.name).to eq('')
      errors = macro.structural_errors
      expect(errors).not_to be_empty # nameは必須なので空文字列はエラー
    end

    it 'beep単独のマクロ' do
      steps = [Cornix::Models::Macro::MacroStep.new(action: 'beep')]
      macro = described_class.new(
        index: 0,
        name: 'Beep',
        description: '',
        sequence: steps
      )

      qmk_array = macro.to_qmk(keycode_converter: keycode_converter)
      expect(qmk_array).to eq([['beep']])
    end

    it '複雑なマクロシーケンス' do
      steps = [
        Cornix::Models::Macro::MacroStep.new(action: 'down', keys: ['LShift']),
        Cornix::Models::Macro::MacroStep.new(action: 'tap', keys: ['A', 'B', 'C']),
        Cornix::Models::Macro::MacroStep.new(action: 'up', keys: ['LShift']),
        Cornix::Models::Macro::MacroStep.new(action: 'delay', duration: 100),
        Cornix::Models::Macro::MacroStep.new(action: 'beep')
      ]
      macro = described_class.new(
        index: 15,
        name: 'Complex',
        description: 'Complex macro',
        sequence: steps
      )

      qmk_array = macro.to_qmk(keycode_converter: keycode_converter)
      expect(qmk_array).to eq([
        ['down', 'KC_LSHIFT'],
        ['tap', 'KC_A', 'KC_B', 'KC_C'],
        ['up', 'KC_LSHIFT'],
        ['delay', 100],
        ['beep']
      ])
    end
  end
end
