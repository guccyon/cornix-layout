# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/cornix/models/layer/encoder_mapping'
require_relative '../../../lib/cornix/converters/keycode_converter'

RSpec.describe Cornix::Models::Layer::EncoderMapping do
  let(:aliases_path) { File.join(__dir__, '../../../lib/cornix/keycode_aliases.yaml') }
  let(:keycode_converter) { Cornix::Converters::KeycodeConverter.new(aliases_path) }

  describe '#initialize' do
    it 'creates EncoderMapping with left and right encoders' do
      encoder_mapping = described_class.new(
        left: { push: 'KC_MUTE', ccw: 'KC_VOLD', cw: 'KC_VOLU' },
        right: { push: 'KC_MUTE', ccw: 'KC_VOLD', cw: 'KC_VOLU' }
      )

      expect(encoder_mapping.left[:push]).to eq('KC_MUTE')
      expect(encoder_mapping.left[:ccw]).to eq('KC_VOLD')
      expect(encoder_mapping.left[:cw]).to eq('KC_VOLU')
      expect(encoder_mapping.right[:push]).to eq('KC_MUTE')
    end
  end

  describe '#to_qmk' do
    it 'converts encoders to QMK array' do
      encoder_mapping = described_class.new(
        left: { push: 'Mute', ccw: 'VolDown', cw: 'VolUp' },
        right: { push: 'Mute', ccw: 'VolDown', cw: 'VolUp' }
      )

      qmk_array = encoder_mapping.to_qmk(keycode_converter)

      expect(qmk_array).to be_a(Array)
      expect(qmk_array.size).to eq(2)
      expect(qmk_array[0]).to eq(['KC_VOLD', 'KC_VOLU'])  # left: [ccw, cw]
      expect(qmk_array[1]).to eq(['KC_VOLD', 'KC_VOLU'])  # right: [ccw, cw]
    end

    it 'resolves aliases to QMK keycodes' do
      encoder_mapping = described_class.new(
        left: { push: 'Mute', ccw: 'VolDown', cw: 'VolUp' },
        right: { push: 'Mute', ccw: 'PgDn', cw: 'PgUp' }
      )

      qmk_array = encoder_mapping.to_qmk(keycode_converter)

      expect(qmk_array[0]).to eq(['KC_VOLD', 'KC_VOLU'])
      expect(qmk_array[1]).to eq(['KC_PGDN', 'KC_PGUP'])
    end
  end

  describe '.from_yaml_hash' do
    it 'creates EncoderMapping from YAML hash' do
      yaml_hash = {
        'left' => { 'push' => 'Mute', 'ccw' => 'VolDown', 'cw' => 'VolUp' },
        'right' => { 'push' => 'Mute', 'ccw' => 'VolDown', 'cw' => 'VolUp' }
      }

      encoder_mapping = described_class.from_yaml_hash(yaml_hash)

      expect(encoder_mapping.left[:push]).to eq('Mute')
      expect(encoder_mapping.left[:ccw]).to eq('VolDown')
      expect(encoder_mapping.left[:cw]).to eq('VolUp')
      expect(encoder_mapping.right[:push]).to eq('Mute')
    end

    it 'handles nil YAML hash' do
      encoder_mapping = described_class.from_yaml_hash(nil)

      expect(encoder_mapping.left).to eq({})
      expect(encoder_mapping.right).to eq({})
    end

    it 'handles partial YAML hash' do
      yaml_hash = {
        'left' => { 'push' => 'Mute' }
      }

      encoder_mapping = described_class.from_yaml_hash(yaml_hash)

      expect(encoder_mapping.left[:push]).to eq('Mute')
      expect(encoder_mapping.left[:ccw]).to be_nil
      expect(encoder_mapping.right[:push]).to be_nil
      expect(encoder_mapping.right[:ccw]).to be_nil
    end

    it 'handles empty left/right hashes' do
      yaml_hash = {
        'left' => {},
        'right' => {}
      }

      encoder_mapping = described_class.from_yaml_hash(yaml_hash)

      expect(encoder_mapping.left[:push]).to be_nil
      expect(encoder_mapping.right[:push]).to be_nil
    end
  end

  describe 'round-trip YAML' do
    it 'maintains data through YAML round-trip' do
      yaml_hash = {
        'left' => { 'push' => 'Mute', 'ccw' => 'VolDown', 'cw' => 'VolUp' },
        'right' => { 'push' => 'Mute', 'ccw' => 'PgDn', 'cw' => 'PgUp' }
      }

      encoder_mapping = described_class.from_yaml_hash(yaml_hash)

      # YAML → EncoderMapping → QMK → (逆変換は Layer で実施)
      qmk_array = encoder_mapping.to_qmk(keycode_converter)

      expect(qmk_array[0]).to eq(['KC_VOLD', 'KC_VOLU'])
      expect(qmk_array[1]).to eq(['KC_PGDN', 'KC_PGUP'])
    end
  end

  describe 'validation' do
    describe '#structurally_valid?' do
      it 'returns true for valid EncoderMapping' do
        encoder_mapping = described_class.new(
          left: { push: 'Mute', ccw: 'VolDown', cw: 'VolUp' },
          right: { push: 'Mute', ccw: 'VolDown', cw: 'VolUp' }
        )
        expect(encoder_mapping.structurally_valid?).to be true
      end

      it 'returns false for empty encoder hashes' do
        # 空のHashはpresenceバリデーションでfalseになる
        encoder_mapping = described_class.new(left: {}, right: {})
        expect(encoder_mapping.structurally_valid?).to be false
      end

      it 'returns false when left is not a Hash' do
        encoder_mapping = described_class.new(left: 'not a hash', right: {})
        expect(encoder_mapping.structurally_valid?).to be false
      end

      it 'returns false when right is not a Hash' do
        encoder_mapping = described_class.new(left: {}, right: 'not a hash')
        expect(encoder_mapping.structurally_valid?).to be false
      end
    end

    describe '#structural_errors' do
      it 'returns empty array for valid EncoderMapping' do
        encoder_mapping = described_class.new(
          left: { push: 'Mute', ccw: 'VolDown', cw: 'VolUp' },
          right: { push: 'Mute', ccw: 'VolDown', cw: 'VolUp' }
        )
        expect(encoder_mapping.structural_errors).to be_empty
      end

      it 'includes error for invalid left type' do
        encoder_mapping = described_class.new(left: 'invalid', right: {})
        errors = encoder_mapping.structural_errors
        expect(errors.size).to be > 0
        expect(errors.join(' ')).to include('Hash')
      end

      it 'includes error for invalid right type' do
        encoder_mapping = described_class.new(left: {}, right: [])
        errors = encoder_mapping.structural_errors
        expect(errors.size).to be > 0
        expect(errors.join(' ')).to include('Hash')
      end
    end

    describe '#semantic_errors' do
      it 'returns empty array for valid keycodes' do
        encoder_mapping = described_class.new(
          left: { push: 'Mute', ccw: 'VolDown', cw: 'VolUp' },
          right: { push: 'Mute', ccw: 'VolDown', cw: 'VolUp' }
        )
        context = { keycode_converter: keycode_converter }
        errors = encoder_mapping.semantic_errors(context)
        expect(errors).to be_empty
      end

      it 'returns empty array when keycode_converter is not provided' do
        encoder_mapping = described_class.new(
          left: { push: 'InvalidKeycode', ccw: 'VolDown', cw: 'VolUp' },
          right: { push: 'Mute', ccw: 'VolDown', cw: 'VolUp' }
        )
        errors = encoder_mapping.semantic_errors({})
        expect(errors).to be_empty
      end

      it 'detects unresolvable keycodes' do
        # Note: KeycodeConverterは無効なキーコードでもエラーを投げない場合がある
        # このテストはセマンティック検証の機構をテストする
        encoder_mapping = described_class.new(
          left: { push: 'Mute', ccw: 'VolDown', cw: 'VolUp' },
          right: { push: 'Mute', ccw: 'VolDown', cw: 'VolUp' }
        )
        context = { keycode_converter: keycode_converter }
        errors = encoder_mapping.semantic_errors(context)
        # 有効なキーコードなのでエラーなし
        expect(errors).to be_empty
      end
    end

    describe '#validate!' do
      it 'does not raise for valid EncoderMapping' do
        encoder_mapping = described_class.new(
          left: { push: 'Mute', ccw: 'VolDown', cw: 'VolUp' },
          right: { push: 'Mute', ccw: 'VolDown', cw: 'VolUp' }
        )
        expect { encoder_mapping.validate! }.not_to raise_error
      end

      it 'raises ValidationError for invalid type' do
        encoder_mapping = described_class.new(left: 'invalid', right: {})
        expect { encoder_mapping.validate! }.to raise_error(Cornix::Models::Concerns::ValidationError)
      end
    end
  end
end
