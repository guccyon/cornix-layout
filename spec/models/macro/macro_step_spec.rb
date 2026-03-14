# frozen_string_literal: true

require_relative '../../spec_helper'
require_relative '../../../lib/cornix/models/macro'
require_relative '../../../lib/cornix/converters/keycode_converter'
require 'tempfile'
require 'yaml'

RSpec.describe Cornix::Models::Macro::MacroStep do
  let(:test_aliases) do
    {
      'aliases' => {
        'A' => 'KC_A',
        'B' => 'KC_B',
        'C' => 'KC_C',
        'Enter' => 'KC_ENT'
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

  describe 'structural validations' do
    it 'action が nil の場合にエラー' do
      step = described_class.new(
        action: nil,
        keys: ['A', 'B']
      )
      errors = step.structural_errors
      expect(errors).not_to be_empty
      expect(errors.join).to include('action')
      expect(errors.join).to match(/cannot be (blank|nil)/i)
    end

    it 'action が空文字列の場合にエラー' do
      step = described_class.new(
        action: '',
        keys: ['A', 'B']
      )
      errors = step.structural_errors
      expect(errors).not_to be_empty
      expect(errors.join).to include('action')
    end

    it 'action が無効な値の場合にエラー' do
      step = described_class.new(
        action: 'invalid_action',
        keys: ['A', 'B']
      )
      errors = step.structural_errors
      expect(errors).not_to be_empty
      expect(errors.join).to include('action')
      expect(errors.join).to match(/invalid_action|not.*valid|must be one of/i)
    end

    it 'tap action で keys が nil の場合にエラー' do
      step = described_class.new(
        action: 'tap',
        keys: nil
      )
      errors = step.structural_errors
      expect(errors).not_to be_empty
      expect(errors.join).to include('keys')
      expect(errors.join).to match(/must be.*Array|required|cannot be nil/i)
    end

    it 'tap action で keys が空配列の場合にエラー' do
      step = described_class.new(
        action: 'tap',
        keys: []
      )
      errors = step.structural_errors
      expect(errors).not_to be_empty
      expect(errors.join).to include('keys')
      expect(errors.join).to match(/cannot be empty|must not be empty/i)
    end

    it 'down action で keys が nil の場合にエラー' do
      step = described_class.new(
        action: 'down',
        keys: nil
      )
      errors = step.structural_errors
      expect(errors).not_to be_empty
      expect(errors.join).to include('keys')
    end

    it 'up action で keys が nil の場合にエラー' do
      step = described_class.new(
        action: 'up',
        keys: nil
      )
      errors = step.structural_errors
      expect(errors).not_to be_empty
      expect(errors.join).to include('keys')
    end

    it 'delay action で duration が nil の場合にエラー' do
      step = described_class.new(
        action: 'delay',
        duration: nil
      )
      errors = step.structural_errors
      expect(errors).not_to be_empty
      expect(errors.join).to include('duration')
      expect(errors.join).to match(/must be.*Integer|required|cannot be nil/i)
    end

    it 'delay action で duration が整数以外の場合にエラー' do
      step = described_class.new(
        action: 'delay',
        duration: 'not_an_integer'
      )
      errors = step.structural_errors
      expect(errors).not_to be_empty
      expect(errors.join).to include('duration')
      expect(errors.join).to match(/must be.*Integer/i)
    end

    it '有効な tap action は構造検証を合格' do
      step = described_class.new(
        action: 'tap',
        keys: ['A', 'B']
      )
      errors = step.structural_errors
      expect(errors).to be_empty
    end

    it '有効な delay action は構造検証を合格' do
      step = described_class.new(
        action: 'delay',
        duration: 250
      )
      errors = step.structural_errors
      expect(errors).to be_empty
    end

    it '有効な beep action は構造検証を合格' do
      step = described_class.new(
        action: 'beep'
      )
      errors = step.structural_errors
      expect(errors).to be_empty
    end
  end

  describe 'semantic validations' do
    it '有効なキーコードを持つMacroStepを検証' do
      step = described_class.new(
        action: 'tap',
        keys: ['A', 'B', 'C']
      )
      errors = step.semantic_errors(context)
      expect(errors).to be_empty
    end

    it '無効なキーコードを含むMacroStepでエラー' do
      step = described_class.new(
        action: 'tap',
        keys: ['A', 'InvalidKey', 'C']
      )
      errors = step.semantic_errors(context)
      expect(errors).not_to be_empty
      expect(errors.join).to include("Invalid keycode 'InvalidKey'")
      expect(errors.join).to include('keys[1]')
    end

    it '複数の無効なキーコードでエラー' do
      step = described_class.new(
        action: 'tap',
        keys: ['Invalid1', 'B', 'Invalid2']
      )
      errors = step.semantic_errors(context)
      expect(errors).not_to be_empty
      expect(errors.join).to include("Invalid keycode 'Invalid1'")
      expect(errors.join).to include("Invalid keycode 'Invalid2'")
    end
  end

  describe '.from_yaml_hash' do
    it 'tap action を YAML Hash から生成' do
      step = described_class.from_yaml_hash({
        'action' => 'tap',
        'keys' => ['A', 'B']
      })

      expect(step.action).to eq('tap')
      expect(step.keys).to eq(['A', 'B'])
      expect(step.duration).to be_nil
    end

    it 'delay action を YAML Hash から生成' do
      step = described_class.from_yaml_hash({
        'action' => 'delay',
        'duration' => 250
      })

      expect(step.action).to eq('delay')
      expect(step.keys).to be_nil
      expect(step.duration).to eq(250)
    end

    it 'beep action を YAML Hash から生成' do
      step = described_class.from_yaml_hash({
        'action' => 'beep'
      })

      expect(step.action).to eq('beep')
      expect(step.keys).to be_nil
      expect(step.duration).to be_nil
    end
  end

  describe '#to_yaml_hash' do
    it 'tap action を YAML Hash に変換' do
      step = described_class.new(
        action: 'tap',
        keys: ['A', 'B']
      )
      hash = step.to_yaml_hash

      expect(hash['action']).to eq('tap')
      expect(hash['keys']).to eq(['A', 'B'])
      expect(hash.key?('duration')).to be false
    end

    it 'delay action を YAML Hash に変換' do
      step = described_class.new(
        action: 'delay',
        duration: 250
      )
      hash = step.to_yaml_hash

      expect(hash['action']).to eq('delay')
      expect(hash['duration']).to eq(250)
      expect(hash.key?('keys')).to be false
    end
  end

  describe '#to_qmk' do
    it 'tap action を QMK 形式に変換' do
      step = described_class.new(
        action: 'tap',
        keys: ['A', 'B']
      )
      qmk = step.to_qmk(keycode_converter)

      expect(qmk).to eq(['tap', 'KC_A', 'KC_B'])
    end

    it 'delay action を QMK 形式に変換' do
      step = described_class.new(
        action: 'delay',
        duration: 250
      )
      qmk = step.to_qmk(keycode_converter)

      expect(qmk).to eq(['delay', 250])
    end

    it 'beep action を QMK 形式に変換' do
      step = described_class.new(
        action: 'beep'
      )
      qmk = step.to_qmk(keycode_converter)

      expect(qmk).to eq(['beep'])
    end
  end
end
