# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require_relative '../../../lib/cornix/models/layer/keycode_value'
require_relative '../../../lib/cornix/converters/keycode_converter'
require_relative '../../../lib/cornix/converters/reference_converter'

RSpec.describe Cornix::Models::Layer::KeycodeValue do
  let(:aliases_path) { File.join(__dir__, '../../../lib/cornix/keycode_aliases.yaml') }
  let(:keycode_converter) { Cornix::Converters::KeycodeConverter.new(aliases_path) }
  let(:config_dir) { File.join(__dir__, '../../fixtures/config') }
  let(:reference_converter) { Cornix::Converters::ReferenceConverter.new(config_dir) }

  before do
    # テスト用の設定ファイルを作成
    FileUtils.mkdir_p("#{config_dir}/macros")
    FileUtils.mkdir_p("#{config_dir}/tap_dance")
    FileUtils.mkdir_p("#{config_dir}/combos")

    File.write("#{config_dir}/macros/00_test_macro.yml", <<~YAML)
      name: Test Macro
      index: 0
      sequence: [{delay: 0, keycodes: [KC_H, KC_I]}]
    YAML

    File.write("#{config_dir}/tap_dance/00_test_tap.yml", <<~YAML)
      name: Test Tap
      index: 0
      on_tap: KC_ESC
      on_hold: KC_LCTL
    YAML

    File.write("#{config_dir}/combos/00_test_combo.yml", <<~YAML)
      name: Test Combo
      index: 0
      keycodes: [KC_A, KC_S]
      keycode: KC_ESC
    YAML
  end

  after do
    FileUtils.rm_rf(config_dir)
  end

  describe '.from_yaml' do
    context 'PlainKeycode' do
      it 'creates PlainKeycode from simple alias' do
        keycode_value = described_class.from_yaml('Tab')
        expect(keycode_value).to be_a(described_class::PlainKeycode)
        expect(keycode_value.raw_value).to eq('Tab')
      end

      it 'creates PlainKeycode from QMK keycode' do
        keycode_value = described_class.from_yaml('KC_TAB')
        expect(keycode_value).to be_a(described_class::PlainKeycode)
        expect(keycode_value.raw_value).to eq('KC_TAB')
      end

      it 'creates PlainKeycode from number' do
        keycode_value = described_class.from_yaml('42')
        expect(keycode_value).to be_a(described_class::PlainKeycode)
        expect(keycode_value.raw_value).to eq('42')
      end

      it 'creates PlainKeycode from nil' do
        keycode_value = described_class.from_yaml(nil)
        expect(keycode_value).to be_a(described_class::PlainKeycode)
      end

      it 'creates PlainKeycode from empty string' do
        keycode_value = described_class.from_yaml('')
        expect(keycode_value).to be_a(described_class::PlainKeycode)
      end
    end

    context 'ReferenceKeycode' do
      it 'creates ReferenceKeycode from name-based macro' do
        keycode_value = described_class.from_yaml("Macro('Test Macro')")
        expect(keycode_value).to be_a(described_class::ReferenceKeycode)
        expect(keycode_value.raw_value).to eq("Macro('Test Macro')")
      end

      it 'creates ReferenceKeycode from index-based macro' do
        keycode_value = described_class.from_yaml('Macro(0)')
        expect(keycode_value).to be_a(described_class::ReferenceKeycode)
        expect(keycode_value.raw_value).to eq('Macro(0)')
      end

      it 'creates ReferenceKeycode from legacy macro' do
        keycode_value = described_class.from_yaml('M0')
        expect(keycode_value).to be_a(described_class::ReferenceKeycode)
        expect(keycode_value.raw_value).to eq('M0')
      end

      it 'creates ReferenceKeycode from TapDance' do
        keycode_value = described_class.from_yaml("TapDance('Test Tap')")
        expect(keycode_value).to be_a(described_class::ReferenceKeycode)
        expect(keycode_value.raw_value).to eq("TapDance('Test Tap')")
      end

      it 'creates ReferenceKeycode from legacy tap dance' do
        keycode_value = described_class.from_yaml('TD(0)')
        expect(keycode_value).to be_a(described_class::ReferenceKeycode)
        expect(keycode_value.raw_value).to eq('TD(0)')
      end

      it 'creates ReferenceKeycode from Combo' do
        keycode_value = described_class.from_yaml("Combo('Test Combo')")
        expect(keycode_value).to be_a(described_class::ReferenceKeycode)
        expect(keycode_value.raw_value).to eq("Combo('Test Combo')")
      end
    end

    context 'FunctionKeycode' do
      it 'creates FunctionKeycode from MO' do
        keycode_value = described_class.from_yaml('MO(1)')
        expect(keycode_value).to be_a(described_class::FunctionKeycode)
        expect(keycode_value.raw_value).to eq('MO(1)')
      end

      it 'creates FunctionKeycode from LSFT' do
        keycode_value = described_class.from_yaml('LSFT(A)')
        expect(keycode_value).to be_a(described_class::FunctionKeycode)
        expect(keycode_value.raw_value).to eq('LSFT(A)')
      end

      it 'creates FunctionKeycode from LT' do
        keycode_value = described_class.from_yaml('LT(2, Space)')
        expect(keycode_value).to be_a(described_class::FunctionKeycode)
        expect(keycode_value.raw_value).to eq('LT(2, Space)')
      end

      it 'creates FunctionKeycode from nested function' do
        keycode_value = described_class.from_yaml('LSFT(LCTL(A))')
        expect(keycode_value).to be_a(described_class::FunctionKeycode)
        expect(keycode_value.raw_value).to eq('LSFT(LCTL(A))')
      end
    end
  end

  describe '#to_s' do
    it 'returns raw_value as string' do
      keycode_value = described_class.from_yaml('Tab')
      expect(keycode_value.to_s).to eq('Tab')
    end

    it 'works for reference keycodes' do
      keycode_value = described_class.from_yaml("Macro('Test')")
      expect(keycode_value.to_s).to eq("Macro('Test')")
    end
  end

  describe 'PlainKeycode#to_qmk' do
    it 'resolves simple alias to QMK code' do
      keycode_value = described_class::PlainKeycode.new(raw_value: 'Tab')
      qmk_code = keycode_value.to_qmk(keycode_converter)
      expect(qmk_code).to eq('KC_TAB')
    end

    it 'resolves QMK keycode to itself' do
      keycode_value = described_class::PlainKeycode.new(raw_value: 'KC_SPACE')
      qmk_code = keycode_value.to_qmk(keycode_converter)
      expect(qmk_code).to eq('KC_SPACE')
    end

    it 'resolves transparent' do
      keycode_value = described_class::PlainKeycode.new(raw_value: 'Trans')
      qmk_code = keycode_value.to_qmk(keycode_converter)
      expect(qmk_code).to eq('KC_TRNS')
    end
  end

  describe 'ReferenceKeycode#to_qmk' do
    it 'resolves name-based macro' do
      keycode_value = described_class::ReferenceKeycode.new(raw_value: "Macro('Test Macro')")
      qmk_code = keycode_value.to_qmk(keycode_converter, reference_converter: reference_converter)
      expect(qmk_code).to eq('M0')
    end

    it 'resolves index-based macro' do
      keycode_value = described_class::ReferenceKeycode.new(raw_value: 'Macro(0)')
      qmk_code = keycode_value.to_qmk(keycode_converter, reference_converter: reference_converter)
      expect(qmk_code).to eq('M0')
    end

    it 'resolves legacy macro' do
      keycode_value = described_class::ReferenceKeycode.new(raw_value: 'M0')
      qmk_code = keycode_value.to_qmk(keycode_converter, reference_converter: reference_converter)
      expect(qmk_code).to eq('M0')
    end

    it 'resolves TapDance' do
      keycode_value = described_class::ReferenceKeycode.new(raw_value: "TapDance('Test Tap')")
      qmk_code = keycode_value.to_qmk(keycode_converter, reference_converter: reference_converter)
      expect(qmk_code).to eq('TD(0)')
    end

    it 'raises error without reference_converter' do
      keycode_value = described_class::ReferenceKeycode.new(raw_value: "Macro('Test')")
      expect {
        keycode_value.to_qmk(keycode_converter)
      }.to raise_error(ArgumentError)
    end
  end

  describe 'FunctionKeycode#to_qmk' do
    it 'resolves MO with layer number' do
      keycode_value = described_class::FunctionKeycode.new(raw_value: 'MO(1)')
      qmk_code = keycode_value.to_qmk(keycode_converter)
      expect(qmk_code).to eq('MO(1)')
    end

    it 'resolves LSFT with number (converts to KC_*)' do
      keycode_value = described_class::FunctionKeycode.new(raw_value: 'LSFT(1)')
      qmk_code = keycode_value.to_qmk(keycode_converter)
      expect(qmk_code).to eq('LSFT(KC_1)')
    end

    it 'resolves LSFT with alias' do
      keycode_value = described_class::FunctionKeycode.new(raw_value: 'LSFT(A)')
      qmk_code = keycode_value.to_qmk(keycode_converter)
      expect(qmk_code).to eq('LSFT(KC_A)')
    end

    it 'resolves LT with layer and keycode' do
      keycode_value = described_class::FunctionKeycode.new(raw_value: 'LT(2, Space)')
      qmk_code = keycode_value.to_qmk(keycode_converter)
      expect(qmk_code).to eq('LT(2, KC_SPACE)')
    end

    it 'resolves nested functions' do
      keycode_value = described_class::FunctionKeycode.new(raw_value: 'LSFT(LCTL(A))')
      qmk_code = keycode_value.to_qmk(keycode_converter)
      expect(qmk_code).to eq('LSFT(LCTL(KC_A))')
    end

    it 'resolves function with macro reference' do
      keycode_value = described_class::FunctionKeycode.new(raw_value: "LT(1, Macro('Test Macro'))")
      qmk_code = keycode_value.to_qmk(keycode_converter, reference_converter: reference_converter)
      expect(qmk_code).to eq('LT(1, M0)')
    end
  end

  describe '.from_qmk' do
    it 'creates PlainKeycode from QMK number' do
      qmk_code = 'KC_TAB'
      keycode_value = described_class.from_qmk(qmk_code, keycode_converter)
      expect(keycode_value).to be_a(described_class::PlainKeycode)
      expect(keycode_value.to_s).to eq('Tab')
    end

    it 'creates PlainKeycode from transparent' do
      qmk_code = 'KC_TRNS'
      keycode_value = described_class.from_qmk(qmk_code, keycode_converter)
      expect(keycode_value).to be_a(described_class::PlainKeycode)
      expect(keycode_value.to_s).to eq('Trans')
    end
  end

  describe 'round-trip' do
    it 'maintains PlainKeycode through round-trip' do
      original = 'Tab'
      keycode_value = described_class.from_yaml(original)
      qmk = keycode_value.to_qmk(keycode_converter)
      restored = described_class.from_qmk(qmk, keycode_converter)
      expect(restored.to_s).to eq(original)
    end

    it 'maintains FunctionKeycode through round-trip (MO)' do
      original = 'MO(1)'
      keycode_value = described_class.from_yaml(original)
      qmk = keycode_value.to_qmk(keycode_converter)
      expect(qmk).to eq('MO(1)')
    end

    it 'maintains FunctionKeycode through round-trip (LSFT)' do
      original = 'LSFT(A)'
      keycode_value = described_class.from_yaml(original)
      qmk = keycode_value.to_qmk(keycode_converter)
      expect(qmk).to eq('LSFT(KC_A)')
    end
  end
end
