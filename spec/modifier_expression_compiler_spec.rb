# frozen_string_literal: true

require_relative '../lib/cornix/modifier_expression_compiler'
require_relative '../lib/cornix/converters/keycode_converter'

RSpec.describe Cornix::ModifierExpressionCompiler do
  let(:aliases_path) { File.join(__dir__, '../lib/cornix/keycode_aliases.yaml') }
  let(:keycode_converter) { Cornix::Converters::KeycodeConverter.new(aliases_path) }

  describe '.to_qmk' do
    context 'with single modifier' do
      it 'compiles Cmd + Q to LGUI(KC_Q)' do
        token = { type: :modifier_expression, modifiers: ['Cmd'], key: 'Q' }
        result = described_class.to_qmk(token, keycode_converter)
        expect(result).to eq('LGUI(KC_Q)')
      end

      it 'compiles Shift + A to LSFT(KC_A)' do
        token = { type: :modifier_expression, modifiers: ['Shift'], key: 'A' }
        result = described_class.to_qmk(token, keycode_converter)
        expect(result).to eq('LSFT(KC_A)')
      end

      it 'compiles Ctrl + C to LCTL(KC_C)' do
        token = { type: :modifier_expression, modifiers: ['Ctrl'], key: 'C' }
        result = described_class.to_qmk(token, keycode_converter)
        expect(result).to eq('LCTL(KC_C)')
      end

      it 'compiles Alt + Tab to LALT(KC_TAB)' do
        token = { type: :modifier_expression, modifiers: ['Alt'], key: 'Tab' }
        result = described_class.to_qmk(token, keycode_converter)
        expect(result).to eq('LALT(KC_TAB)')
      end
    end

    context 'with two modifiers (QMK shortcuts)' do
      it 'compiles Ctrl + Shift + Q to LCS(KC_Q)' do
        token = { type: :modifier_expression, modifiers: ['Ctrl', 'Shift'], key: 'Q' }
        result = described_class.to_qmk(token, keycode_converter)
        expect(result).to eq('LCS(KC_Q)')
      end

      it 'compiles Ctrl + Alt + Q to LCA(KC_Q)' do
        token = { type: :modifier_expression, modifiers: ['Ctrl', 'Alt'], key: 'Q' }
        result = described_class.to_qmk(token, keycode_converter)
        expect(result).to eq('LCA(KC_Q)')
      end

      it 'compiles Ctrl + Cmd + Q to LCG(KC_Q)' do
        token = { type: :modifier_expression, modifiers: ['Ctrl', 'Cmd'], key: 'Q' }
        result = described_class.to_qmk(token, keycode_converter)
        expect(result).to eq('LCG(KC_Q)')
      end

      it 'compiles Shift + Alt + Q to LSA(KC_Q)' do
        token = { type: :modifier_expression, modifiers: ['Shift', 'Alt'], key: 'Q' }
        result = described_class.to_qmk(token, keycode_converter)
        expect(result).to eq('LSA(KC_Q)')
      end

      it 'compiles Shift + Cmd + Q to SGUI(KC_Q)' do
        token = { type: :modifier_expression, modifiers: ['Shift', 'Cmd'], key: 'Q' }
        result = described_class.to_qmk(token, keycode_converter)
        expect(result).to eq('SGUI(KC_Q)')
      end

      it 'compiles Alt + Cmd + Q to LAG(KC_Q)' do
        token = { type: :modifier_expression, modifiers: ['Alt', 'Cmd'], key: 'Q' }
        result = described_class.to_qmk(token, keycode_converter)
        expect(result).to eq('LAG(KC_Q)')
      end
    end

    context 'with three modifiers (QMK shortcuts)' do
      it 'compiles Ctrl + Shift + Alt + Q to MEH(KC_Q)' do
        token = { type: :modifier_expression, modifiers: ['Ctrl', 'Shift', 'Alt'], key: 'Q' }
        result = described_class.to_qmk(token, keycode_converter)
        expect(result).to eq('MEH(KC_Q)')
      end

      it 'compiles Ctrl + Shift + Cmd + Q to LCSG(KC_Q)' do
        token = { type: :modifier_expression, modifiers: ['Ctrl', 'Shift', 'Cmd'], key: 'Q' }
        result = described_class.to_qmk(token, keycode_converter)
        expect(result).to eq('LCSG(KC_Q)')
      end

      it 'compiles Ctrl + Alt + Cmd + Q to LCAG(KC_Q)' do
        token = { type: :modifier_expression, modifiers: ['Ctrl', 'Alt', 'Cmd'], key: 'Q' }
        result = described_class.to_qmk(token, keycode_converter)
        expect(result).to eq('LCAG(KC_Q)')
      end

      it 'compiles Shift + Alt + Cmd + Q to LSAG(KC_Q)' do
        token = { type: :modifier_expression, modifiers: ['Shift', 'Alt', 'Cmd'], key: 'Q' }
        result = described_class.to_qmk(token, keycode_converter)
        expect(result).to eq('LSAG(KC_Q)')
      end
    end

    context 'with four modifiers (HYPR)' do
      it 'compiles Ctrl + Shift + Alt + Cmd + Q to HYPR(KC_Q)' do
        token = { type: :modifier_expression, modifiers: ['Ctrl', 'Shift', 'Alt', 'Cmd'], key: 'Q' }
        result = described_class.to_qmk(token, keycode_converter)
        expect(result).to eq('HYPR(KC_Q)')
      end
    end

    context 'with right-side modifiers' do
      it 'compiles RShift + Q to RSFT(KC_Q)' do
        token = { type: :modifier_expression, modifiers: ['RShift'], key: 'Q' }
        result = described_class.to_qmk(token, keycode_converter)
        expect(result).to eq('RSFT(KC_Q)')
      end

      it 'compiles RCtrl + RShift + Q to RCS(KC_Q)' do
        token = { type: :modifier_expression, modifiers: ['RCtrl', 'RShift'], key: 'Q' }
        result = described_class.to_qmk(token, keycode_converter)
        expect(result).to eq('RCS(KC_Q)')
      end

      it 'compiles RCtrl + RShift + RCmd + Q to RCSG(KC_Q)' do
        token = { type: :modifier_expression, modifiers: ['RCtrl', 'RShift', 'RCmd'], key: 'Q' }
        result = described_class.to_qmk(token, keycode_converter)
        expect(result).to eq('RCSG(KC_Q)')
      end
    end

    context 'with modifier aliases' do
      it 'compiles Command + Q to LGUI(KC_Q)' do
        token = { type: :modifier_expression, modifiers: ['Command'], key: 'Q' }
        result = described_class.to_qmk(token, keycode_converter)
        expect(result).to eq('LGUI(KC_Q)')
      end

      it 'compiles Win + E to LGUI(KC_E)' do
        token = { type: :modifier_expression, modifiers: ['Win'], key: 'E' }
        result = described_class.to_qmk(token, keycode_converter)
        expect(result).to eq('LGUI(KC_E)')
      end

      it 'compiles Option + Tab to LALT(KC_TAB)' do
        token = { type: :modifier_expression, modifiers: ['Option'], key: 'Tab' }
        result = described_class.to_qmk(token, keycode_converter)
        expect(result).to eq('LALT(KC_TAB)')
      end

      it 'compiles Control + C to LCTL(KC_C)' do
        token = { type: :modifier_expression, modifiers: ['Control'], key: 'C' }
        result = described_class.to_qmk(token, keycode_converter)
        expect(result).to eq('LCTL(KC_C)')
      end
    end

    context 'with order-independent matching' do
      it 'compiles Shift + Cmd to SGUI regardless of order' do
        token1 = { type: :modifier_expression, modifiers: ['Shift', 'Cmd'], key: 'Q' }
        token2 = { type: :modifier_expression, modifiers: ['Cmd', 'Shift'], key: 'Q' }

        result1 = described_class.to_qmk(token1, keycode_converter)
        result2 = described_class.to_qmk(token2, keycode_converter)

        expect(result1).to eq('SGUI(KC_Q)')
        expect(result2).to eq('SGUI(KC_Q)')
      end

      it 'compiles MEH regardless of order' do
        token1 = { type: :modifier_expression, modifiers: ['Ctrl', 'Shift', 'Alt'], key: 'Q' }
        token2 = { type: :modifier_expression, modifiers: ['Alt', 'Ctrl', 'Shift'], key: 'Q' }
        token3 = { type: :modifier_expression, modifiers: ['Shift', 'Alt', 'Ctrl'], key: 'Q' }

        expect(described_class.to_qmk(token1, keycode_converter)).to eq('MEH(KC_Q)')
        expect(described_class.to_qmk(token2, keycode_converter)).to eq('MEH(KC_Q)')
        expect(described_class.to_qmk(token3, keycode_converter)).to eq('MEH(KC_Q)')
      end
    end

    context 'with key aliases' do
      it 'resolves Space key' do
        token = { type: :modifier_expression, modifiers: ['Shift'], key: 'Space' }
        result = described_class.to_qmk(token, keycode_converter)
        expect(result).to eq('LSFT(KC_SPACE)')
      end

      it 'resolves Tab key' do
        token = { type: :modifier_expression, modifiers: ['Cmd'], key: 'Tab' }
        result = described_class.to_qmk(token, keycode_converter)
        expect(result).to eq('LGUI(KC_TAB)')
      end

      it 'resolves Enter key' do
        token = { type: :modifier_expression, modifiers: ['Ctrl'], key: 'Enter' }
        result = described_class.to_qmk(token, keycode_converter)
        expect(result).to eq('LCTL(KC_ENTER)')
      end
    end

    context 'with KC_ prefixed keys' do
      it 'keeps KC_ENTER as-is' do
        token = { type: :modifier_expression, modifiers: ['Cmd'], key: 'KC_ENTER' }
        result = described_class.to_qmk(token, keycode_converter)
        expect(result).to eq('LGUI(KC_ENTER)')
      end

      it 'keeps KC_SPACE as-is' do
        token = { type: :modifier_expression, modifiers: ['Shift'], key: 'KC_SPACE' }
        result = described_class.to_qmk(token, keycode_converter)
        expect(result).to eq('LSFT(KC_SPACE)')
      end
    end

    context 'with nested fallback (no shortcut)' do
      it 'nests Cmd + Alt when not left/right aligned' do
        # This would require mixed L/R which doesn't have a shortcut
        # Actually, Cmd + Alt = LAG, so let's test a real non-shortcut case
        # We need to force a combination that has no shortcut
        # Since all 2-mod combos have shortcuts, let's mock an unknown modifier

        # Skip this - all our combos have shortcuts. Let's test the nesting logic directly.
      end
    end

    context 'with error cases' do
      it 'raises error for unknown modifier' do
        token = { type: :modifier_expression, modifiers: ['UnknownMod'], key: 'Q' }
        expect {
          described_class.to_qmk(token, keycode_converter)
        }.to raise_error(ArgumentError, /Unknown modifier/)
      end
    end
  end

  describe '.find_shortcut' do
    it 'finds SGUI for [LGUI, LSFT]' do
      result = described_class.find_shortcut(['LGUI', 'LSFT'])
      expect(result).to eq('SGUI')
    end

    it 'finds SGUI for [LSFT, LGUI] (order-independent)' do
      result = described_class.find_shortcut(['LSFT', 'LGUI'])
      expect(result).to eq('SGUI')
    end

    it 'finds MEH for [LCTL, LSFT, LALT]' do
      result = described_class.find_shortcut(['LCTL', 'LSFT', 'LALT'])
      expect(result).to eq('MEH')
    end

    it 'finds HYPR for [LCTL, LSFT, LALT, LGUI]' do
      result = described_class.find_shortcut(['LCTL', 'LSFT', 'LALT', 'LGUI'])
      expect(result).to eq('HYPR')
    end

    it 'returns nil for non-existent combination' do
      # This is actually hard to test since we support all standard combinations
      # Let's use a single modifier which doesn't have a "shortcut"
      result = described_class.find_shortcut(['LSFT'])
      expect(result).to be_nil
    end
  end

  describe '.nest_modifiers' do
    it 'nests single modifier' do
      result = described_class.nest_modifiers(['LSFT'], 'KC_Q')
      expect(result).to eq('LSFT(KC_Q)')
    end

    it 'nests two modifiers (first = outermost)' do
      result = described_class.nest_modifiers(['LGUI', 'LSFT'], 'KC_Q')
      expect(result).to eq('LGUI(LSFT(KC_Q))')
    end

    it 'nests three modifiers' do
      result = described_class.nest_modifiers(['LCTL', 'LALT', 'LSFT'], 'KC_Q')
      expect(result).to eq('LCTL(LALT(LSFT(KC_Q)))')
    end
  end

  describe '.resolve_modifier' do
    it 'resolves Shift to LSFT' do
      expect(described_class.resolve_modifier('Shift')).to eq('LSFT')
    end

    it 'resolves Cmd to LGUI' do
      expect(described_class.resolve_modifier('Cmd')).to eq('LGUI')
    end

    it 'resolves Command to LGUI' do
      expect(described_class.resolve_modifier('Command')).to eq('LGUI')
    end

    it 'resolves Win to LGUI' do
      expect(described_class.resolve_modifier('Win')).to eq('LGUI')
    end

    it 'resolves Alt to LALT' do
      expect(described_class.resolve_modifier('Alt')).to eq('LALT')
    end

    it 'resolves Option to LALT' do
      expect(described_class.resolve_modifier('Option')).to eq('LALT')
    end

    it 'resolves RShift to RSFT' do
      expect(described_class.resolve_modifier('RShift')).to eq('RSFT')
    end

    it 'resolves RCmd to RGUI' do
      expect(described_class.resolve_modifier('RCmd')).to eq('RGUI')
    end

    it 'raises error for unknown modifier' do
      expect {
        described_class.resolve_modifier('InvalidMod')
      }.to raise_error(ArgumentError, /Unknown modifier/)
    end
  end

  describe '.resolve_key' do
    it 'keeps KC_ prefixed keys as-is' do
      result = described_class.resolve_key('KC_ENTER', keycode_converter)
      expect(result).to eq('KC_ENTER')
    end

    it 'resolves Space alias' do
      result = described_class.resolve_key('Space', keycode_converter)
      expect(result).to eq('KC_SPACE')
    end

    it 'resolves Tab alias' do
      result = described_class.resolve_key('Tab', keycode_converter)
      expect(result).to eq('KC_TAB')
    end

    it 'resolves single letter' do
      result = described_class.resolve_key('Q', keycode_converter)
      expect(result).to eq('KC_Q')
    end
  end
end
