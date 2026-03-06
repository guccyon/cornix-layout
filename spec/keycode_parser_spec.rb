# frozen_string_literal: true

require_relative '../lib/cornix/keycode_parser'

RSpec.describe Cornix::KeycodeParser do
  describe '.parse' do
    context 'with reference functions' do
      it 'parses name-based Macro reference' do
        result = described_class.parse("Macro('End of Line')")
        expect(result).to eq({
          type: :reference,
          function: 'Macro',
          args: [{ type: :string, value: 'End of Line' }]
        })
      end

      it 'parses name-based TapDance reference' do
        result = described_class.parse("TapDance('Escape or Layer')")
        expect(result).to eq({
          type: :reference,
          function: 'TapDance',
          args: [{ type: :string, value: 'Escape or Layer' }]
        })
      end

      it 'parses name-based Combo reference' do
        result = described_class.parse("Combo('Bracket Combo')")
        expect(result).to eq({
          type: :reference,
          function: 'Combo',
          args: [{ type: :string, value: 'Bracket Combo' }]
        })
      end

      it 'parses index-based Macro reference' do
        result = described_class.parse('Macro(3)')
        expect(result).to eq({
          type: :reference,
          function: 'Macro',
          args: [{ type: :number, value: 3 }]
        })
      end

      it 'parses index-based TapDance reference' do
        result = described_class.parse('TapDance(2)')
        expect(result).to eq({
          type: :reference,
          function: 'TapDance',
          args: [{ type: :number, value: 2 }]
        })
      end

      it 'parses reference with double quotes' do
        result = described_class.parse('Macro("Double Quoted")')
        expect(result).to eq({
          type: :reference,
          function: 'Macro',
          args: [{ type: :string, value: 'Double Quoted' }]
        })
      end

      it 'parses reference with special characters in name' do
        result = described_class.parse("Macro('Copy/Paste Cmd+C')")
        expect(result).to eq({
          type: :reference,
          function: 'Macro',
          args: [{ type: :string, value: 'Copy/Paste Cmd+C' }]
        })
      end

      it 'treats invalid reference format as unknown' do
        result = described_class.parse('Macro(InvalidArg)')
        expect(result[:type]).to eq(:unknown)
      end
    end

    context 'with function calls' do
      it 'parses simple function with numeric argument' do
        result = described_class.parse('MO(3)')
        expect(result).to eq({
          type: :function,
          name: 'MO',
          args: [{ type: :number, value: 3 }]
        })
      end

      it 'parses function with alias argument' do
        result = described_class.parse('LSFT(A)')
        expect(result).to eq({
          type: :function,
          name: 'LSFT',
          args: [{ type: :alias, value: 'A' }]
        })
      end

      it 'parses function with multiple arguments' do
        result = described_class.parse('LT(1, Space)')
        expect(result).to eq({
          type: :function,
          name: 'LT',
          args: [
            { type: :number, value: 1 },
            { type: :alias, value: 'Space' }
          ]
        })
      end

      it 'parses function with QMK keycode argument' do
        result = described_class.parse('LSFT(KC_A)')
        expect(result).to eq({
          type: :function,
          name: 'LSFT',
          args: [{ type: :keycode, value: 'KC_A' }]
        })
      end

      it 'parses nested function calls' do
        result = described_class.parse('LT(2, LSFT(A))')
        expect(result).to eq({
          type: :function,
          name: 'LT',
          args: [
            { type: :number, value: 2 },
            {
              type: :function,
              name: 'LSFT',
              args: [{ type: :alias, value: 'A' }]
            }
          ]
        })
      end

      it 'parses function with numbered suffix' do
        result = described_class.parse('LT0(1, A)')
        expect(result).to eq({
          type: :function,
          name: 'LT0',
          args: [
            { type: :number, value: 1 },
            { type: :alias, value: 'A' }
          ]
        })
      end
    end

    context 'with QMK keycodes' do
      it 'parses KC_TAB' do
        result = described_class.parse('KC_TAB')
        expect(result).to eq({ type: :keycode, value: 'KC_TAB' })
      end

      it 'parses KC_SPACE' do
        result = described_class.parse('KC_SPACE')
        expect(result).to eq({ type: :keycode, value: 'KC_SPACE' })
      end

      it 'parses KC_TRANSPARENT' do
        result = described_class.parse('KC_TRANSPARENT')
        expect(result).to eq({ type: :keycode, value: 'KC_TRANSPARENT' })
      end

      it 'parses KC_F13' do
        result = described_class.parse('KC_F13')
        expect(result).to eq({ type: :keycode, value: 'KC_F13' })
      end
    end

    context 'with legacy formats' do
      it 'parses legacy macro M0' do
        result = described_class.parse('M0')
        expect(result).to eq({ type: :legacy_macro, value: 'M0' })
      end

      it 'parses legacy macro M11' do
        result = described_class.parse('M11')
        expect(result).to eq({ type: :legacy_macro, value: 'M11' })
      end

      it 'parses legacy tap dance TD(0)' do
        result = described_class.parse('TD(0)')
        expect(result).to eq({ type: :legacy_tap_dance, value: 'TD(0)' })
      end

      it 'parses legacy tap dance TD(12)' do
        result = described_class.parse('TD(12)')
        expect(result).to eq({ type: :legacy_tap_dance, value: 'TD(12)' })
      end
    end

    context 'with aliases' do
      it 'parses simple alias' do
        result = described_class.parse('Tab')
        expect(result).to eq({ type: :alias, value: 'Tab' })
      end

      it 'parses alias with underscore' do
        result = described_class.parse('Left_Shift')
        expect(result).to eq({ type: :alias, value: 'Left_Shift' })
      end

      it 'parses Trans alias' do
        result = described_class.parse('Trans')
        expect(result).to eq({ type: :alias, value: 'Trans' })
      end

      it 'parses alias with special symbols' do
        result = described_class.parse('___')
        expect(result).to eq({ type: :alias, value: '___' })
      end
    end

    context 'with numbers' do
      it 'parses pure number' do
        result = described_class.parse('3')
        expect(result).to eq({ type: :number, value: 3 })
      end

      it 'parses zero' do
        result = described_class.parse('0')
        expect(result).to eq({ type: :number, value: 0 })
      end

      it 'parses large number' do
        result = described_class.parse('42')
        expect(result).to eq({ type: :number, value: 42 })
      end
    end

    context 'with edge cases' do
      it 'returns nil for nil input' do
        result = described_class.parse(nil)
        expect(result).to be_nil
      end

      it 'returns -1 for -1 input' do
        result = described_class.parse(-1)
        expect(result).to eq(-1)
      end

      it 'returns empty string for empty string' do
        result = described_class.parse('')
        expect(result).to eq('')
      end

      it 'handles integer input' do
        result = described_class.parse(42)
        expect(result).to eq({ type: :number, value: 42 })
      end

      it 'handles whitespace' do
        result = described_class.parse('  Tab  ')
        expect(result).to eq({ type: :alias, value: 'Tab' })
      end
    end

    context 'with complex nested structures' do
      it 'parses deeply nested functions' do
        result = described_class.parse('LT(1, LSFT(LCTL(A)))')
        expect(result[:type]).to eq(:function)
        expect(result[:name]).to eq('LT')
        expect(result[:args][0]).to eq({ type: :number, value: 1 })
        expect(result[:args][1][:type]).to eq(:function)
        expect(result[:args][1][:name]).to eq('LSFT')
        expect(result[:args][1][:args][0][:type]).to eq(:function)
        expect(result[:args][1][:args][0][:name]).to eq('LCTL')
      end

      it 'parses function with reference inside' do
        result = described_class.parse("LT(1, Macro('Test'))")
        expect(result[:type]).to eq(:function)
        expect(result[:args][1][:type]).to eq(:reference)
        expect(result[:args][1][:function]).to eq('Macro')
      end
    end
  end

  describe '.parse_arguments' do
    it 'parses single argument' do
      args = described_class.parse_arguments('3')
      expect(args).to eq([{ type: :number, value: 3 }])
    end

    it 'parses multiple arguments' do
      args = described_class.parse_arguments('1, Space')
      expect(args).to eq([
        { type: :number, value: 1 },
        { type: :alias, value: 'Space' }
      ])
    end

    it 'parses arguments with nested parentheses' do
      args = described_class.parse_arguments('1, LSFT(A)')
      expect(args).to eq([
        { type: :number, value: 1 },
        {
          type: :function,
          name: 'LSFT',
          args: [{ type: :alias, value: 'A' }]
        }
      ])
    end

    it 'handles commas inside strings' do
      args = described_class.parse_arguments("'Hello, World'")
      expect(args).to eq([{ type: :string, value: 'Hello, World' }])
    end

    it 'handles multiple arguments with strings containing commas' do
      args = described_class.parse_arguments("'First, Name', 'Last, Name'")
      expect(args).to eq([
        { type: :string, value: 'First, Name' },
        { type: :string, value: 'Last, Name' }
      ])
    end

    it 'handles empty arguments' do
      args = described_class.parse_arguments('')
      expect(args).to eq([])
    end
  end

  describe '.unparse' do
    it 'unparses name-based Macro reference' do
      token = {
        type: :reference,
        function: 'Macro',
        args: [{ type: :string, value: 'End of Line' }]
      }
      result = described_class.unparse(token)
      expect(result).to eq("Macro('End of Line')")
    end

    it 'unparses index-based Macro reference' do
      token = {
        type: :reference,
        function: 'Macro',
        args: [{ type: :number, value: 3 }]
      }
      result = described_class.unparse(token)
      expect(result).to eq('Macro(3)')
    end

    it 'unparses function with multiple arguments' do
      token = {
        type: :function,
        name: 'LT',
        args: [
          { type: :number, value: 1 },
          { type: :alias, value: 'Space' }
        ]
      }
      result = described_class.unparse(token)
      expect(result).to eq('LT(1, Space)')
    end

    it 'unparses QMK keycode' do
      token = { type: :keycode, value: 'KC_TAB' }
      result = described_class.unparse(token)
      expect(result).to eq('KC_TAB')
    end

    it 'unparses legacy macro' do
      token = { type: :legacy_macro, value: 'M0' }
      result = described_class.unparse(token)
      expect(result).to eq('M0')
    end

    it 'unparses alias' do
      token = { type: :alias, value: 'Tab' }
      result = described_class.unparse(token)
      expect(result).to eq('Tab')
    end

    it 'unparses number' do
      token = { type: :number, value: 42 }
      result = described_class.unparse(token)
      expect(result).to eq('42')
    end

    it 'returns nil for nil input' do
      result = described_class.unparse(nil)
      expect(result).to be_nil
    end

    it 'returns -1 for -1 input' do
      result = described_class.unparse(-1)
      expect(result).to eq(-1)
    end

    it 'handles string input' do
      result = described_class.unparse('Tab')
      expect(result).to eq('Tab')
    end

    it 'handles integer input' do
      result = described_class.unparse(42)
      expect(result).to eq('42')
    end

    it 'escapes single quotes in string values' do
      token = {
        type: :reference,
        function: 'Macro',
        args: [{ type: :string, value: "It's working" }]
      }
      result = described_class.unparse(token)
      expect(result).to eq("Macro('It\\'s working')")
    end
  end

  describe 'round-trip parsing' do
    shared_examples 'round-trip parser' do |input|
      it "round-trips: #{input}" do
        parsed = described_class.parse(input)
        unparsed = described_class.unparse(parsed)
        expect(unparsed).to eq(input)
      end
    end

    include_examples 'round-trip parser', "Macro('End of Line')"
    include_examples 'round-trip parser', 'Macro(3)'
    include_examples 'round-trip parser', "TapDance('Escape')"
    include_examples 'round-trip parser', 'TapDance(0)'
    include_examples 'round-trip parser', 'MO(3)'
    include_examples 'round-trip parser', 'LT(1, Space)'
    include_examples 'round-trip parser', 'LSFT(A)'
    include_examples 'round-trip parser', 'KC_TAB'
    include_examples 'round-trip parser', 'M0'
    include_examples 'round-trip parser', 'TD(2)'
    include_examples 'round-trip parser', 'Tab'
    include_examples 'round-trip parser', '3'
  end

  describe '.token_type' do
    it 'identifies reference' do
      expect(described_class.token_type("Macro('Test')")).to eq(:reference)
    end

    it 'identifies function' do
      expect(described_class.token_type('MO(3)')).to eq(:function)
    end

    it 'identifies keycode' do
      expect(described_class.token_type('KC_TAB')).to eq(:keycode)
    end

    it 'identifies legacy_macro' do
      expect(described_class.token_type('M0')).to eq(:legacy_macro)
    end

    it 'identifies legacy_tap_dance' do
      expect(described_class.token_type('TD(2)')).to eq(:legacy_tap_dance)
    end

    it 'identifies alias' do
      expect(described_class.token_type('Tab')).to eq(:alias)
    end

    it 'identifies number' do
      expect(described_class.token_type('42')).to eq(:number)
    end
  end

  describe '.reference?' do
    it 'returns true for Macro reference' do
      expect(described_class.reference?("Macro('Test')")).to be true
    end

    it 'returns true for TapDance reference' do
      expect(described_class.reference?('TapDance(2)')).to be true
    end

    it 'returns false for function' do
      expect(described_class.reference?('MO(3)')).to be false
    end

    it 'returns false for legacy format' do
      expect(described_class.reference?('M0')).to be false
    end
  end

  describe '.legacy?' do
    it 'returns true for M0' do
      expect(described_class.legacy?('M0')).to be true
    end

    it 'returns true for TD(2)' do
      expect(described_class.legacy?('TD(2)')).to be true
    end

    it 'returns false for Macro reference' do
      expect(described_class.legacy?("Macro('Test')")).to be false
    end

    it 'returns false for function' do
      expect(described_class.legacy?('MO(3)')).to be false
    end
  end

  describe '.function?' do
    it 'returns true for MO(3)' do
      expect(described_class.function?('MO(3)')).to be true
    end

    it 'returns true for LSFT(A)' do
      expect(described_class.function?('LSFT(A)')).to be true
    end

    it 'returns false for Macro reference' do
      expect(described_class.function?("Macro('Test')")).to be false
    end

    it 'returns false for keycode' do
      expect(described_class.function?('KC_TAB')).to be false
    end
  end

  describe 'modifier expressions' do
    context 'parsing' do
      it 'parses simple modifier expression' do
        result = described_class.parse('Cmd + Q')
        expect(result).to eq({
          type: :modifier_expression,
          modifiers: ['Cmd'],
          key: 'Q'
        })
      end

      it 'parses two modifier expression' do
        result = described_class.parse('Shift + Cmd + Q')
        expect(result).to eq({
          type: :modifier_expression,
          modifiers: ['Shift', 'Cmd'],
          key: 'Q'
        })
      end

      it 'parses three modifier expression' do
        result = described_class.parse('Ctrl + Shift + Alt + A')
        expect(result).to eq({
          type: :modifier_expression,
          modifiers: ['Ctrl', 'Shift', 'Alt'],
          key: 'A'
        })
      end

      it 'parses four modifier expression (HYPR)' do
        result = described_class.parse('Ctrl + Shift + Alt + Cmd + Q')
        expect(result).to eq({
          type: :modifier_expression,
          modifiers: ['Ctrl', 'Shift', 'Alt', 'Cmd'],
          key: 'Q'
        })
      end

      it 'handles flexible spacing (no spaces)' do
        result = described_class.parse('Cmd+Q')
        expect(result).to eq({
          type: :modifier_expression,
          modifiers: ['Cmd'],
          key: 'Q'
        })
      end

      it 'handles flexible spacing (extra spaces)' do
        result = described_class.parse('Cmd  +  Q')
        expect(result).to eq({
          type: :modifier_expression,
          modifiers: ['Cmd'],
          key: 'Q'
        })
      end

      it 'parses right-side modifiers' do
        result = described_class.parse('RShift + RCmd + Q')
        expect(result).to eq({
          type: :modifier_expression,
          modifiers: ['RShift', 'RCmd'],
          key: 'Q'
        })
      end

      it 'parses modifier aliases (Command)' do
        result = described_class.parse('Command + Q')
        expect(result).to eq({
          type: :modifier_expression,
          modifiers: ['Command'],
          key: 'Q'
        })
      end

      it 'parses modifier aliases (Win)' do
        result = described_class.parse('Win + E')
        expect(result).to eq({
          type: :modifier_expression,
          modifiers: ['Win'],
          key: 'E'
        })
      end

      it 'parses modifier aliases (Option)' do
        result = described_class.parse('Option + Tab')
        expect(result).to eq({
          type: :modifier_expression,
          modifiers: ['Option'],
          key: 'Tab'
        })
      end

      it 'parses modifier aliases (Control)' do
        result = described_class.parse('Control + C')
        expect(result).to eq({
          type: :modifier_expression,
          modifiers: ['Control'],
          key: 'C'
        })
      end

      it 'parses key with KC_ prefix' do
        result = described_class.parse('Cmd + KC_ENTER')
        expect(result).to eq({
          type: :modifier_expression,
          modifiers: ['Cmd'],
          key: 'KC_ENTER'
        })
      end

      it 'parses key with alias' do
        result = described_class.parse('Shift + Space')
        expect(result).to eq({
          type: :modifier_expression,
          modifiers: ['Shift'],
          key: 'Space'
        })
      end

      it 'does not parse plus sign as key' do
        # "Shift + +" won't match the pattern since '+' is not \w+
        result = described_class.parse('Shift + +')
        expect(result[:type]).to eq(:alias) # Falls through to alias
      end

      it 'does not parse function calls as modifier expression' do
        # "Cmd + LT(1, Space)" won't match because of parentheses
        result = described_class.parse('Cmd + LT(1, Space)')
        expect(result[:type]).to eq(:alias) # Falls through
      end
    end

    context 'unparsing' do
      it 'unparses simple modifier expression' do
        token = { type: :modifier_expression, modifiers: ['Cmd'], key: 'Q' }
        result = described_class.unparse(token)
        expect(result).to eq('Cmd + Q')
      end

      it 'unparses two modifier expression' do
        token = { type: :modifier_expression, modifiers: ['Shift', 'Cmd'], key: 'Q' }
        result = described_class.unparse(token)
        expect(result).to eq('Shift + Cmd + Q')
      end

      it 'unparses three modifier expression' do
        token = { type: :modifier_expression, modifiers: ['Ctrl', 'Shift', 'Alt'], key: 'A' }
        result = described_class.unparse(token)
        expect(result).to eq('Ctrl + Shift + Alt + A')
      end
    end

    context 'round-trip' do
      it 'preserves simple modifier expression' do
        original = 'Cmd + Q'
        parsed = described_class.parse(original)
        unparsed = described_class.unparse(parsed)
        expect(unparsed).to eq(original)
      end

      it 'normalizes spacing' do
        original = 'Cmd+Q'
        parsed = described_class.parse(original)
        unparsed = described_class.unparse(parsed)
        expect(unparsed).to eq('Cmd + Q')
      end

      it 'preserves multiple modifiers' do
        original = 'Ctrl + Shift + Alt + Q'
        parsed = described_class.parse(original)
        unparsed = described_class.unparse(parsed)
        expect(unparsed).to eq(original)
      end
    end
  end
end
