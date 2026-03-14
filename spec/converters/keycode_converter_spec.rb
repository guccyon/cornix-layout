# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../lib/cornix/converters/keycode_converter'
require 'tempfile'
require 'yaml'

RSpec.describe Cornix::Converters::KeycodeConverter do
  let(:test_aliases) do
    {
      'aliases' => {
        'A' => 'KC_A',
        'LShift' => 'KC_LSHIFT',
        'Space' => 'KC_SPACE',
        'Enter' => 'KC_ENTER',
        'Trans' => 'KC_TRNS',
        'Transparent' => 'KC_TRNS',
        '___' => 'KC_TRNS',
        'Tab' => 'KC_TAB',
        'NoKey' => 'KC_NO'
      },
      'char_keycodes' => {
        'a' => 'KC_A',
        'z' => 'KC_Z',
        'A' => 'LSFT(KC_A)',
        ' ' => 'KC_SPACE',
        '(' => 'KC_LEFT_PAREN',
        '!' => 'KC_EXCLAIM'
      }
    }
  end

  let(:yaml_file) do
    file = Tempfile.new(['keycode_aliases', '.yaml'])
    file.write(YAML.dump(test_aliases))
    file.close
    file
  end

  let(:resolver) { described_class.new(yaml_file.path) }

  after do
    yaml_file.unlink
  end

  describe '#resolve' do
    it 'resolves alias to QMK keycode' do
      expect(resolver.resolve('A')).to eq('KC_A')
      expect(resolver.resolve('LShift')).to eq('KC_LSHIFT')
    end

    it 'returns original keycode if no alias exists' do
      expect(resolver.resolve('KC_TAB')).to eq('KC_TAB')
    end

    it 'resolves transparent aliases' do
      expect(resolver.resolve('Trans')).to eq('KC_TRNS')
      expect(resolver.resolve('Transparent')).to eq('KC_TRNS')
      expect(resolver.resolve('___')).to eq('KC_TRNS')
    end

    it 'resolves NoKey alias' do
      expect(resolver.resolve('NoKey')).to eq('KC_NO')
    end

    it 'handles case sensitivity' do
      # Aliases are case-sensitive
      expect(resolver.resolve('a')).to be_nil # not found, invalid keycode
      expect(resolver.resolve('A')).to eq('KC_A') # found
    end
  end

  describe '#reverse_resolve' do
    it 'finds alias for QMK keycode' do
      expect(resolver.reverse_resolve('KC_A')).to eq('A')
      expect(resolver.reverse_resolve('KC_LSHIFT')).to eq('LShift')
    end

    it 'returns original keycode if no alias exists' do
      expect(resolver.reverse_resolve('KC_XYZ_UNKNOWN')).to eq('KC_XYZ_UNKNOWN')
    end

    it 'returns first defined alias when multiple aliases exist' do
      # KC_TRNS has three aliases: Trans, Transparent, ___
      # Should return the first one in definition order
      result = resolver.reverse_resolve('KC_TRNS')
      expect(['Trans', 'Transparent', '___']).to include(result)
      # In our test data, 'Trans' is defined first
      expect(result).to eq('Trans')
    end

    it 'handles KC_NO correctly' do
      expect(resolver.reverse_resolve('KC_NO')).to eq('NoKey')
    end
  end

  describe 'with system keycode_aliases.yaml' do
    let(:system_resolver) do
      aliases_path = File.join(__dir__, '../../lib/cornix/keycode_aliases.yaml')
      described_class.new(aliases_path)
    end

    it 'loads system aliases successfully' do
      expect { system_resolver }.not_to raise_error
    end

    it 'resolves common aliases from system file' do
      expect(system_resolver.resolve('Tab')).to eq('KC_TAB')
      expect(system_resolver.resolve('Enter')).to eq('KC_ENTER')
      expect(system_resolver.resolve('Space')).to eq('KC_SPACE')
    end

    it 'reverse resolves common keycodes from system file' do
      expect(system_resolver.reverse_resolve('KC_TAB')).to eq('Tab')
      expect(system_resolver.reverse_resolve('KC_ENTER')).to eq('Enter')
      expect(system_resolver.reverse_resolve('KC_SPACE')).to eq('Space')
    end

    it 'handles modifier keycodes' do
      expect(system_resolver.resolve('LShift')).to match(/KC_L(SH|SFT)/)
      expect(system_resolver.resolve('LCtrl')).to eq('KC_LCTRL')
    end
  end

  describe 'edge cases' do
    it 'handles nil gracefully' do
      expect(resolver.resolve(nil)).to be_nil # nil is valid (represents no key)
    end

    it 'handles empty string' do
      expect(resolver.resolve('')).to be_nil # empty string is invalid keycode
    end

    it 'handles numeric input' do
      # Numbers should be returned as-is since they're not in the alias map
      expect(resolver.resolve('1')).to eq('1')
      expect(resolver.resolve('42')).to eq('42')
    end

    it 'handles already resolved QMK keycodes' do
      expect(resolver.resolve('KC_A')).to eq('KC_A')
      expect(resolver.resolve('KC_LSHIFT')).to eq('KC_LSHIFT')
    end

    it 'handles function-style keycodes' do
      # Function calls should be returned as-is
      expect(resolver.resolve('MO(1)')).to eq('MO(1)')
      expect(resolver.resolve('LT(2, Space)')).to eq('LT(2, Space)')
    end

    it 'returns nil for invalid keycodes' do
      # Invalid keycodes should return nil
      expect(resolver.resolve('Tabbbb')).to be_nil
      expect(resolver.resolve('Invalid_Key')).to be_nil
      expect(resolver.resolve('xyz')).to be_nil
      expect(resolver.resolve('lower_case')).to be_nil
    end

    it 'handles QMK custom keycodes (USER*, RGB_*, etc)' do
      # QMK custom keycodes should be accepted as-is
      expect(resolver.resolve('USER00')).to eq('USER00')
      expect(resolver.resolve('USER06')).to eq('USER06')
      expect(resolver.resolve('RGB_TOG')).to eq('RGB_TOG')
      expect(resolver.resolve('AU_ON')).to eq('AU_ON')
      expect(resolver.resolve('QK_BOOT')).to eq('QK_BOOT')
    end
  end

  describe 'initialization' do
    it 'raises error when file does not exist' do
      expect {
        described_class.new('/nonexistent/path/keycode_aliases.yaml')
      }.to raise_error(Errno::ENOENT)
    end

    it 'handles malformed YAML gracefully' do
      malformed_file = Tempfile.new(['malformed', '.yaml'])
      malformed_file.write("invalid: yaml: content: [")
      malformed_file.close

      expect {
        described_class.new(malformed_file.path)
      }.to raise_error(Psych::SyntaxError)

      malformed_file.unlink
    end

    it 'handles YAML without aliases key' do
      no_aliases_file = Tempfile.new(['no_aliases', '.yaml'])
      no_aliases_file.write(YAML.dump({ 'some_other_key' => 'value' }))
      no_aliases_file.close

      resolver = described_class.new(no_aliases_file.path)
      expect(resolver.resolve('A')).to be_nil # No aliases, invalid keycode
      expect(resolver.resolve('KC_A')).to eq('KC_A') # KC_* format is valid

      no_aliases_file.unlink
    end
  end

  describe '#resolve_char' do
    it '小文字をKC_Xに変換する' do
      expect(resolver.resolve_char('a')).to eq('KC_A')
      expect(resolver.resolve_char('z')).to eq('KC_Z')
    end

    it '大文字をLSFT(KC_X)に変換する' do
      expect(resolver.resolve_char('A')).to eq('LSFT(KC_A)')
    end

    it 'スペースをKC_SPACEに変換する' do
      expect(resolver.resolve_char(' ')).to eq('KC_SPACE')
    end

    it '記号を変換する' do
      expect(resolver.resolve_char('(')).to eq('KC_LEFT_PAREN')
      expect(resolver.resolve_char('!')).to eq('KC_EXCLAIM')
    end

    it 'char_keycodes にない文字はnilを返す' do
      expect(resolver.resolve_char("\x01")).to be_nil
      expect(resolver.resolve_char('b')).to be_nil  # not in test fixture
    end
  end
end
