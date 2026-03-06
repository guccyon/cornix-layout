# frozen_string_literal: true

module Cornix
  # KeycodeParser - Centralized parser for all mapping value syntax
  #
  # Purpose:
  #   Parse and tokenize mapping values before resolution. Centralizes syntax
  #   parsing and makes future extensions (modifier syntax) easy to add.
  #
  # Responsibilities:
  #   1. Parse mapping value strings (e.g., "Macro('End of Line')", "LSFT(A)")
  #   2. Tokenize into structured format (function name, arguments, nesting)
  #   3. Identify token types (reference, keycode, alias, function)
  #   4. Handle nested functions and complex syntax
  #   5. Provide reverse parsing (structured format → string)
  #
  # Token Types:
  #   :reference       - Macro('Name'), TapDance(2), Combo('Name')
  #   :function        - MO(3), LSFT(A), LT(1, Space)
  #   :keycode         - KC_TAB, KC_SPACE
  #   :legacy_macro    - M0, M11
  #   :legacy_tap_dance - TD(2)
  #   :modifier_expression - Cmd + Q, Shift + Ctrl + A
  #   :alias           - Tab, Space, Trans
  #   :number          - 3, 42 (for layer numbers, indices)
  #   :string          - 'End of Line', "Bracket Combo"
  #
  # Example:
  #   parsed = KeycodeParser.parse("Macro('End of Line')")
  #   # => { type: :reference, function: 'Macro', args: [{ type: :string, value: 'End of Line' }] }
  #
  #   original = KeycodeParser.unparse(parsed)
  #   # => "Macro('End of Line')"
  #
  class KeycodeParser
    # Parse mapping value string into structured token
    #
    # @param keycode [String, Integer] The keycode to parse
    # @return [Hash, Integer, nil] Structured token or original value if nil/-1
    def self.parse(keycode)
      return keycode if keycode.nil? || keycode == '' || keycode == -1

      keycode_str = keycode.to_s.strip
      return keycode if keycode_str.empty?

      # Pattern 1: Reference functions - Macro(), TapDance(), Combo()
      if match = keycode_str.match(/^(Macro|TapDance|Combo)\((.*)\)$/m)
        function_name = match[1]
        arg = match[2].strip

        # Name-based: Macro('End of Line') or Macro("End of Line")
        if string_match = arg.match(/^(['"])(.*)\1$/m)
          string_value = string_match[2]
          return {
            type: :reference,
            function: function_name,
            args: [{ type: :string, value: string_value }]
          }
        elsif arg.match?(/^\d+$/)
          # Index-based: Macro(3)
          return {
            type: :reference,
            function: function_name,
            args: [{ type: :number, value: arg.to_i }]
          }
        else
          # Invalid reference format - treat as unknown
          return { type: :unknown, value: keycode_str }
        end
      end

      # Pattern 2: Legacy tap dance - TD(2) (must come before generic function pattern)
      if keycode_str.match?(/^TD\(\d+\)$/)
        return { type: :legacy_tap_dance, value: keycode_str }
      end

      # Pattern 3: Modifier expressions - Cmd + Q, Shift + Ctrl + A
      # Must come before generic function pattern to avoid false positives
      if keycode_str.match?(/^(\w+)(\s*\+\s*\w+)+$/)
        return parse_modifier_expression(keycode_str)
      end

      # Pattern 4: Function calls - MO(3), LSFT(A), LT(1, Space)
      if match = keycode_str.match(/^([A-Z_]+[0-9]*)\((.*)\)$/m)
        function_name = match[1]
        arguments = match[2]

        # Parse arguments (comma-separated, can be nested)
        args = parse_arguments(arguments)

        return {
          type: :function,
          name: function_name,
          args: args
        }
      end

      # Pattern 5: QMK keycode - KC_TAB, KC_SPACE
      if keycode_str.match?(/^KC_[A-Z0-9_]+$/)
        return { type: :keycode, value: keycode_str }
      end

      # Pattern 6: Legacy macro - M0, M11
      if keycode_str.match?(/^M\d+$/)
        return { type: :legacy_macro, value: keycode_str }
      end

      # Pattern 7: Pure number (for layer indices, etc.)
      if keycode_str.match?(/^\d+$/)
        return { type: :number, value: keycode_str.to_i }
      end

      # Pattern 8: String literals (for testing)
      if string_match = keycode_str.match(/^(['"])(.*)\1$/m)
        return { type: :string, value: string_match[2] }
      end

      # Pattern 9: Alias or unknown
      { type: :alias, value: keycode_str }
    end

    # Parse modifier expression (e.g., "Cmd + Q", "Shift + Ctrl + A")
    #
    # @param expr [String] The modifier expression string
    # @return [Hash] Structured token with modifiers and key
    def self.parse_modifier_expression(expr)
      # Split by '+' with flexible spacing
      parts = expr.split(/\s*\+\s*/).map(&:strip)

      # Last part is the key, everything else is modifiers
      modifiers = parts[0..-2]
      key = parts[-1]

      {
        type: :modifier_expression,
        modifiers: modifiers,
        key: key
      }
    end

    # Parse function arguments (handles nesting and commas)
    #
    # @param args_string [String] Comma-separated argument string
    # @return [Array<Hash>] Array of parsed argument tokens
    def self.parse_arguments(args_string)
      args = []
      current_arg = +""  # Unfreeze the string with unary +
      depth = 0
      in_string = false
      string_char = nil

      args_string.each_char do |char|
        case char
        when "'", '"'
          if !in_string
            in_string = true
            string_char = char
          elsif char == string_char
            in_string = false
            string_char = nil
          end
          current_arg << char

        when '('
          depth += 1 unless in_string
          current_arg << char

        when ')'
          depth -= 1 unless in_string
          current_arg << char

        when ','
          if depth == 0 && !in_string
            # Argument boundary
            trimmed = current_arg.strip
            args << parse(trimmed) unless trimmed.empty?
            current_arg = +""  # Create new unfrozen string
          else
            current_arg << char
          end

        else
          current_arg << char
        end
      end

      # Add last argument
      trimmed = current_arg.strip
      args << parse(trimmed) unless trimmed.empty?

      args
    end

    # Convert parsed token back to string
    #
    # @param token [Hash, Integer, String, nil] The token to unparse
    # @return [String, Integer, nil] Original string representation
    def self.unparse(token)
      return token if token.nil? || token == -1
      return token.to_s if token.is_a?(Integer) || token.is_a?(String)

      unless token.is_a?(Hash)
        return token.to_s
      end

      case token[:type]
      when :reference
        function = token[:function]
        arg = token[:args][0]

        if arg[:type] == :string
          # Escape single quotes in the string value
          escaped_value = arg[:value].to_s.gsub("'") { "\\'" }
          "#{function}('#{escaped_value}')"
        else
          "#{function}(#{arg[:value]})"
        end

      when :function
        name = token[:name]
        args = token[:args].map { |a| unparse(a) }.join(', ')
        "#{name}(#{args})"

      when :modifier_expression
        modifiers = token[:modifiers].join(' + ')
        key = token[:key]
        "#{modifiers} + #{key}"

      when :keycode, :legacy_macro, :legacy_tap_dance, :alias
        token[:value].to_s

      when :number
        token[:value].to_s

      when :string
        # Escape single quotes
        escaped_value = token[:value].to_s.gsub("'") { "\\'" }
        "'#{escaped_value}'"

      when :unknown
        token[:value].to_s

      else
        token.to_s
      end
    end

    # Identify token type for quick checks
    #
    # @param keycode [String, Integer] The keycode to identify
    # @return [Symbol] Token type (:reference, :function, :keycode, etc.)
    def self.token_type(keycode)
      parsed = parse(keycode)
      parsed.is_a?(Hash) ? parsed[:type] : :unknown
    end

    # Check if a keycode is a reference function (Macro, TapDance, Combo)
    #
    # @param keycode [String] The keycode to check
    # @return [Boolean] True if it's a reference function
    def self.reference?(keycode)
      token_type(keycode) == :reference
    end

    # Check if a keycode is a legacy format (M0, TD(2))
    #
    # @param keycode [String] The keycode to check
    # @return [Boolean] True if it's legacy format
    def self.legacy?(keycode)
      type = token_type(keycode)
      type == :legacy_macro || type == :legacy_tap_dance
    end

    # Check if a keycode is a function call
    #
    # @param keycode [String] The keycode to check
    # @return [Boolean] True if it's a function call
    def self.function?(keycode)
      token_type(keycode) == :function
    end
  end
end
