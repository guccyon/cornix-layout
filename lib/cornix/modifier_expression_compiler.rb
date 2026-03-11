# frozen_string_literal: true

module Cornix
  # ModifierExpressionCompiler - Compiles modifier expressions to QMK format
  #
  # Purpose:
  #   Convert VS Code-style modifier expressions (e.g., "Cmd + Q") to QMK format
  #   with automatic shortcut detection (e.g., LSG, MEH, HYPR).
  #
  # Features:
  #   - Order-independent shortcut matching (Cmd + Shift = Shift + Cmd → LSG)
  #   - Comprehensive QMK shortcut support (20+ combinations)
  #   - Fallback to nested functions when no shortcut exists
  #   - Platform-neutral aliases (Cmd/Command/Win, Alt/Option)
  #
  # Example:
  #   token = { type: :modifier_expression, modifiers: ['Cmd', 'Shift'], key: 'Q' }
  #   qmk = ModifierExpressionCompiler.to_qmk(token, keycode_converter)
  #   # => "LSG(KC_Q)"
  #
  class ModifierExpressionCompiler
    # QMK modifier shortcuts (order-independent)
    # Format: sorted modifier array => QMK shortcut function
    SHORTCUTS = {
      # 4 modifiers
      ['LALT', 'LCTL', 'LGUI', 'LSFT'] => 'HYPR',

      # 3 modifiers (left)
      ['LALT', 'LCTL', 'LSFT'] => 'MEH',
      ['LCTL', 'LGUI', 'LSFT'] => 'LCSG',
      ['LALT', 'LCTL', 'LGUI'] => 'LCAG',
      ['LALT', 'LGUI', 'LSFT'] => 'LSAG',

      # 3 modifiers (right)
      ['RALT', 'RCTL', 'RSFT'] => 'MEH', # Right MEH uses same name
      ['RCTL', 'RGUI', 'RSFT'] => 'RCSG',
      ['RALT', 'RCTL', 'RGUI'] => 'RCAG',
      ['RALT', 'RGUI', 'RSFT'] => 'RSAG',

      # 2 modifiers (left)
      ['LCTL', 'LSFT'] => 'LCS',
      ['LALT', 'LCTL'] => 'LCA',
      ['LCTL', 'LGUI'] => 'LCG',
      ['LALT', 'LSFT'] => 'LSA',
      ['LGUI', 'LSFT'] => 'LSG',
      ['LALT', 'LGUI'] => 'LAG',

      # 2 modifiers (right)
      ['RCTL', 'RSFT'] => 'RCS',
      ['RALT', 'RCTL'] => 'RCA',
      ['RCTL', 'RGUI'] => 'RCG',
      ['RALT', 'RSFT'] => 'RSA',
      ['RGUI', 'RSFT'] => 'RSG',
      ['RALT', 'RGUI'] => 'RAG'
    }.freeze

    # Modifier name to QMK function mapping
    MODIFIER_TO_FUNCTION = {
      # Left modifiers (default)
      'Shift' => 'LSFT',
      'Ctrl' => 'LCTL',
      'Control' => 'LCTL',
      'Alt' => 'LALT',
      'Option' => 'LALT',
      'Cmd' => 'LGUI',
      'Command' => 'LGUI',
      'Win' => 'LGUI',
      'Gui' => 'LGUI',

      # Right modifiers (explicit)
      'RShift' => 'RSFT',
      'RCtrl' => 'RCTL',
      'RControl' => 'RCTL',
      'RAlt' => 'RALT',
      'ROption' => 'RALT',
      'RCmd' => 'RGUI',
      'RCommand' => 'RGUI',
      'RWin' => 'RGUI',
      'RGui' => 'RGUI'
    }.freeze

    # Convert modifier expression token to QMK format
    #
    # @param token [Hash] Parsed modifier expression token
    # @param keycode_converter [KeycodeConverter] Converter for key resolution
    # @return [String] QMK format (e.g., "LSG(KC_Q)" or "LGUI(LSFT(KC_Q))")
    def self.to_qmk(token, keycode_converter)
      modifiers = token[:modifiers]
      key = token[:key]

      # Resolve modifier names to QMK functions
      mod_functions = modifiers.map { |mod| resolve_modifier(mod) }

      # Resolve key to QMK keycode
      resolved_key = resolve_key(key, keycode_converter)

      # Try to find a QMK shortcut (order-independent)
      shortcut = find_shortcut(mod_functions)

      if shortcut
        # Use shortcut: LSG(KC_Q)
        "#{shortcut}(#{resolved_key})"
      else
        # Fallback to nested functions: LGUI(LSFT(KC_Q))
        nest_modifiers(mod_functions, resolved_key)
      end
    end

    # Find QMK shortcut for given modifiers (order-independent)
    #
    # @param mod_functions [Array<String>] QMK modifier functions
    # @return [String, nil] QMK shortcut or nil if not found
    def self.find_shortcut(mod_functions)
      sorted_mods = mod_functions.sort
      SHORTCUTS[sorted_mods]
    end

    # Nest modifiers as functions (fallback when no shortcut exists)
    #
    # @param mod_functions [Array<String>] QMK modifier functions
    # @param key [String] Resolved key
    # @return [String] Nested QMK format
    def self.nest_modifiers(mod_functions, key)
      # Nest from outside to inside: first modifier = outermost
      result = key
      mod_functions.reverse.each do |mod|
        result = "#{mod}(#{result})"
      end
      result
    end

    # Resolve modifier name to QMK function
    #
    # @param name [String] Modifier name (e.g., 'Cmd', 'Shift')
    # @return [String] QMK function (e.g., 'LGUI', 'LSFT')
    # @raise [ArgumentError] If modifier name is unknown
    def self.resolve_modifier(name)
      MODIFIER_TO_FUNCTION[name] || raise(ArgumentError, "Unknown modifier: #{name}")
    end

    # Resolve key to QMK keycode
    #
    # @param key [String] Key name (can be alias or QMK keycode)
    # @param converter [KeycodeConverter] Converter for aliases
    # @return [String] QMK keycode (e.g., 'KC_Q', 'KC_SPACE')
    def self.resolve_key(key, converter)
      # If already QMK format, return as-is
      return key if key.start_with?('KC_')

      # Otherwise, resolve via KeycodeConverter
      resolved = converter.resolve(key)

      # If resolution failed, assume it's a raw keycode
      resolved || key
    end
  end
end
