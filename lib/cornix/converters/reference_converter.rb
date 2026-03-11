# frozen_string_literal: true

require 'yaml'

module Cornix
  module Converters
    # ReferenceConverter - Resolve macro/tap dance/combo references
    #
    # Purpose:
    #   Resolve references to macros, tap dances, and combos using name or index.
    #   Provides bidirectional resolution (name↔index) and validation.
    #
    # Responsibilities:
    #   1. Load and cache metadata from config files (macros, tap_dance, combos)
    #   2. Build bidirectional mappings: name↔index
    #   3. Resolve references (name/index → QMK format)
    #   4. Reverse-resolve (QMK format → name/index)
    #   5. Validate references exist and are well-formed
    #
    # Caching Strategy:
    #   - Lazy load: Only load files when first reference is resolved
    #   - Cache lifetime: Persists for instance lifetime
    #   - Cache invalidation: clear_cache() method for FileRenamer
    #   - Memory footprint: ~7 KB (30 macros × 50 bytes × 3 types)
    #
    # Example:
    #   resolver = ReferenceConverter.new('config')
    #
    #   # Resolve reference to QMK format
    #   token = { type: :reference, function: 'Macro', args: [{type: :string, value: 'End of Line'}] }
    #   qmk = resolver.resolve(token)  # => "M5"
  #
  #   # Reverse resolve QMK to name-based token
  #   token = resolver.reverse_resolve("M5", prefer_name: true)
  #   # => { type: :reference, function: 'Macro', args: [{type: :string, value: 'End of Line'}] }
    #
    class ReferenceConverter
      # Initialize resolver with config directory
    #
    # @param config_dir [String] Path to config directory
    def initialize(config_dir)
      @config_dir = config_dir
      @cache = {
        macros: nil,
        tap_dance: nil,
        combos: nil
      }
    end

    # Resolve reference to QMK format
    #
    # @param token [Hash] Parsed token from KeycodeParser
    # @return [String] QMK format (M3, TD(2), etc.)
    # @raise [StandardError] If reference not found or invalid
    def resolve(token)
      return nil unless token.is_a?(Hash) && token[:type] == :reference

      function_name = token[:function]
      arg = token[:args][0]

      type = function_to_type(function_name)
      return nil unless type

      if arg[:type] == :string
        # Name-based: Macro('End of Line') → M5
        name = arg[:value]
        index = name_to_index(type, name)

        if index.nil?
          raise "#{function_name} '#{name}' not found in config/#{type}/"
        end

        format_qmk(type, index)

      elsif arg[:type] == :number
        # Index-based: Macro(3) → M3
        index = arg[:value]

        # Validate index exists
        unless index_exists?(type, index)
          raise "#{function_name} index #{index} not found in config/#{type}/"
        end

        format_qmk(type, index)

      else
        raise "Invalid reference argument type: #{arg[:type]}"
      end
    end

    # Reverse resolve QMK format to structured token
    #
    # @param qmk_keycode [String] QMK format (M3, TD(2), etc.)
    # @param prefer_name [Boolean] Prefer name-based format if available
    # @return [Hash] Structured token (KeycodeParser format)
    def reverse_resolve(qmk_keycode, prefer_name: true)
      # Match legacy macro: M0, M11
      if match = qmk_keycode.match(/^M(\d+)$/)
        index = match[1].to_i
        return reverse_resolve_macro(index, prefer_name)
      end

      # Match legacy tap dance: TD(2)
      if match = qmk_keycode.match(/^TD\((\d+)\)$/)
        index = match[1].to_i
        return reverse_resolve_tap_dance(index, prefer_name)
      end

      # Not a reference - return as-is
      nil
    end

    # Validate that a reference exists
    #
    # @param token [Hash] Parsed token from KeycodeParser
    # @return [Hash] { valid: true/false, error: "..." }
    def validate_reference(token)
      return { valid: false, error: 'Invalid token format' } unless token.is_a?(Hash) && token[:type] == :reference

      function_name = token[:function]
      arg = token[:args][0]

      type = function_to_type(function_name)
      unless type
        return { valid: false, error: "Unknown reference function: #{function_name}" }
      end

      if arg[:type] == :string
        # Name-based reference
        name = arg[:value]
        if name_to_index(type, name).nil?
          return { valid: false, error: "#{function_name} '#{name}' not found" }
        end

      elsif arg[:type] == :number
        # Index-based reference
        index = arg[:value]

        # Validate range (QMK max: 32)
        if index < 0 || index >= 32
          return { valid: false, error: "#{function_name} index #{index} out of range (0-31)" }
        end

        # Validate index exists
        unless index_exists?(type, index)
          return { valid: false, error: "#{function_name} index #{index} not found" }
        end

      else
        return { valid: false, error: "Invalid argument type: #{arg[:type]}" }
      end

      { valid: true }
    end

    # Clear cache (for FileRenamer after updates)
    def clear_cache
      @cache = {
        macros: nil,
        tap_dance: nil,
        combos: nil
      }
    end

    private

    # Convert function name to type symbol
    def function_to_type(function_name)
      case function_name
      when 'Macro' then :macros
      when 'TapDance' then :tap_dance
      when 'Combo' then :combos
      else nil
      end
    end

    # Load metadata for a type (lazy loading)
    def load_metadata(type)
      return @cache[type] if @cache[type]

      by_name = {}
      by_index = {}

      dir = File.join(@config_dir, type.to_s)
      return @cache[type] = { by_name: by_name, by_index: by_index } unless Dir.exist?(dir)

      Dir.glob("#{dir}/*.{yaml,yml}").sort.each do |file|
        data = YAML.load_file(file)
        next unless data

        index = data['index']
        name = data['name']

        next unless index && name

        by_index[index] = name
        by_name[name] = index
      end

      @cache[type] = { by_name: by_name, by_index: by_index }
    end

    # Get index from name
    def name_to_index(type, name)
      metadata = load_metadata(type)
      metadata[:by_name][name]
    end

    # Get name from index
    def index_to_name(type, index)
      metadata = load_metadata(type)
      metadata[:by_index][index]
    end

    # Check if index exists
    def index_exists?(type, index)
      metadata = load_metadata(type)
      metadata[:by_index].key?(index)
    end

    # Format QMK keycode
    def format_qmk(type, index)
      case type
      when :macros then "M#{index}"
      when :tap_dance then "TD(#{index})"
      when :combos then "COMBO(#{index})"
      else raise "Unknown type: #{type}"
      end
    end

    # Reverse resolve macro
    def reverse_resolve_macro(index, prefer_name)
      if prefer_name
        name = index_to_name(:macros, index)
        if name
          return {
            type: :reference,
            function: 'Macro',
            args: [{ type: :string, value: name }]
          }
        end
      end

      # Fallback to index-based
      {
        type: :reference,
        function: 'Macro',
        args: [{ type: :number, value: index }]
      }
    end

    # Reverse resolve tap dance
    def reverse_resolve_tap_dance(index, prefer_name)
      if prefer_name
        name = index_to_name(:tap_dance, index)
        if name
          return {
            type: :reference,
            function: 'TapDance',
            args: [{ type: :string, value: name }]
          }
        end
      end

      # Fallback to index-based
      {
        type: :reference,
        function: 'TapDance',
                args: [{ type: :number, value: index }]
      }
    end
  end
end
end
