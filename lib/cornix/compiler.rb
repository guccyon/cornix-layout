# frozen_string_literal: true

require 'json'
require 'yaml'
require_relative 'keycode_resolver'
require_relative 'keycode_parser'
require_relative 'reference_resolver'
require_relative 'modifier_expression_compiler'
require_relative 'position_map'

module Cornix
  # YAML設定ファイルをlayout.vilに変換するコンパイラ
  class Compiler
    def initialize(config_dir)
      @config_dir = config_dir
      # lib/cornix/keycode_aliases.yaml を直接参照
      aliases_path = File.join(__dir__, 'keycode_aliases.yaml')
      @keycode_resolver = KeycodeResolver.new(aliases_path)
      @reference_resolver = ReferenceResolver.new(config_dir)
      @position_map = PositionMap.new("#{config_dir}/position_map.yaml")
    end

    def compile(output_path)
      metadata = load_yaml('metadata.yaml')
      layers_data = compile_layers
      encoder_data = compile_encoders
      macros_data = compile_macros
      tap_dance_data = compile_tap_dance
      combos_data = compile_combos
      settings_data = compile_settings

      vil_data = {
        'version' => metadata['version'],
        'uid' => metadata['uid'],
        'layout' => layers_data,
        'encoder_layout' => encoder_data,
        'layout_options' => metadata['layout_options'],
        'macro' => macros_data,
        'vial_protocol' => metadata['vial_protocol'],
        'via_protocol' => metadata['via_protocol'],
        'tap_dance' => tap_dance_data,
        'combo' => combos_data,
        'key_override' => [],
        'alt_repeat_key' => [],
        'settings' => settings_data
      }

      File.write(output_path, JSON.generate(vil_data))
      puts "✓ Compiled: #{output_path}"
    end

    private

    # エイリアスをQMKキーコードに変換
    def resolve_to_qmk(keycode)
      return keycode if keycode.nil? || keycode == '' || keycode == -1

      # Parse using KeycodeParser
      parsed = KeycodeParser.parse(keycode)

      case parsed[:type]
      when :keycode
        # Already QMK format - pass through
        parsed[:value]

      when :reference
        # Delegate to ReferenceResolver
        begin
          @reference_resolver.resolve(parsed)
        rescue => e
          # If resolution fails, return original keycode
          warn "Warning: #{e.message}"
          keycode
        end

      when :legacy_macro, :legacy_tap_dance
        # Legacy format - pass through
        parsed[:value]

      when :modifier_expression
        # Delegate to ModifierExpressionCompiler
        ModifierExpressionCompiler.to_qmk(parsed, @keycode_resolver)

      when :function
        # Handle function calls (MO, LSFT, LT, etc.)
        function_name = parsed[:name]
        args = parsed[:args]

        # Recursively resolve arguments
        resolved_args = args.map do |arg|
          if arg[:type] == :number
            # Layer switching functions: preserve numeric args
            if function_name.match?(/^(MO|TO|OSL|TG|TT|DF|LT\d*|TD|COMBO)$/)
              arg[:value]
            else
              # Modifier functions: convert to KC_*
              "KC_#{arg[:value]}"
            end
          else
            # Recursively resolve non-numeric args
            resolve_to_qmk(KeycodeParser.unparse(arg))
          end
        end

        "#{function_name}(#{resolved_args.join(', ')})"

      when :alias
        # Delegate to KeycodeResolver
        resolved = @keycode_resolver.resolve(parsed[:value])
        resolved != parsed[:value] ? resolved : parsed[:value]

      when :number
        # Standalone number → KC_*
        "KC_#{parsed[:value]}"

      else
        # Unknown - return as-is
        keycode
      end
    end

    def compile_layers
      layer_files = Dir.glob("#{@config_dir}/layers/*.{yaml,yml}").sort_by do |file|
        File.basename(file).match(/^(\d+)_/)[1].to_i
      end

      layers = Array.new(10) { empty_layer }

      layer_files.each do |file|
        index = File.basename(file).match(/^(\d+)_/)[1].to_i
        layer_config = YAML.load_file(file)

        if index == 0
          layers[index] = compile_base_layer(layer_config)
        else
          layers[index] = compile_override_layer(layer_config, layers[0])
        end
      end

      layers
    end

    def compile_base_layer(config)
      layer = empty_layer
      mapping = config['mapping']

      # 左手（通常キー）
      4.times do |row_idx|
        6.times do |col_idx|
          symbol = @position_map.symbol_at(:left, row_idx, col_idx)
          next unless symbol

          keycode = mapping[symbol]
          layer[row_idx][col_idx] = resolve_to_qmk(keycode || 'KC_NO')
        end
      end

      # 左手ロータリープッシュ (row2, col6)
      layer[2][6] = resolve_to_qmk(mapping['l_rotary_push']) if mapping['l_rotary_push']
      layer[2][6] ||= -1

      # 右手（通常キー）
      # Cornixの右手側は物理的に右から左にインデックスが振られているため、列を逆転
      # row3も含めて全行で逆順処理を適用
      4.times do |row_idx|
        # row3の場合は最初の3列のみ（cols 0-2）、他は6列
        max_col = (row_idx == 3) ? 3 : 6

        max_col.times do |col_idx|
          symbol = @position_map.symbol_at(:right, row_idx, col_idx)
          next unless symbol

          keycode = mapping[symbol]

          # 全行で逆順処理
          # row0-2: 5 - col_idx (6要素の場合)
          # row3: 2 - col_idx (3要素の場合)
          if row_idx == 3
            hardware_col_idx = 2 - col_idx
          else
            hardware_col_idx = 5 - col_idx
          end

          layer[row_idx + 4][hardware_col_idx] = resolve_to_qmk(keycode || 'KC_NO')
        end
      end

      # 右手ロータリープッシュ (row1, col6)
      layer[5][6] = resolve_to_qmk(mapping['r_rotary_push']) if mapping['r_rotary_push']
      layer[5][6] ||= -1

      # 親指キー
      # 左手親指キー（Row 3, Cols 3-5）
      ['thumb_l_left', 'thumb_l_middle', 'thumb_l_right'].each_with_index do |symbol, idx|
        col_idx = 3 + idx
        if mapping[symbol]
          layer[3][col_idx] = resolve_to_qmk(mapping[symbol])
        else
          layer[3][col_idx] = resolve_to_qmk('KC_NO')
        end
      end

      # 右手親指キー（Row 7, Cols 5-3 逆順）
      ['thumb_r_left', 'thumb_r_middle', 'thumb_r_right'].each_with_index do |symbol, idx|
        col_idx = 5 - idx  # 逆順: 5, 4, 3
        if mapping[symbol]
          layer[7][col_idx] = resolve_to_qmk(mapping[symbol])
        else
          layer[7][col_idx] = resolve_to_qmk('KC_NO')
        end
      end

      layer
    end

    def compile_override_layer(config, base_layer)
      layer = deep_copy(base_layer)
      overrides = config['overrides'] || {}

      # 左手（通常キー）
      4.times do |row_idx|
        6.times do |col_idx|
          symbol = @position_map.symbol_at(:left, row_idx, col_idx)
          next unless symbol

          if overrides.key?(symbol)
            value = overrides[symbol]
            # "Trans" や "Transparent" は KC_TRNS に変換
            layer[row_idx][col_idx] = resolve_to_qmk(value)
          end
        end
      end

      # 左手ロータリープッシュ (row2, col6)
      if overrides.key?('l_rotary_push')
        layer[2][6] = resolve_to_qmk(overrides['l_rotary_push'])
      end

      # 左手親指キー
      ['thumb_l_left', 'thumb_l_middle', 'thumb_l_right'].each_with_index do |symbol, idx|
        if overrides.key?(symbol)
          col_idx = 3 + idx
          layer[3][col_idx] = resolve_to_qmk(overrides[symbol])
        end
      end

      # 右手（通常キー）
      # Cornixの右手側は物理的に右から左にインデックスが振られているため、列を逆転
      # row3も含めて全行で逆順処理を適用
      4.times do |row_idx|
        # row3の場合は最初の3列のみ（cols 0-2）、他は6列
        max_col = (row_idx == 3) ? 3 : 6

        max_col.times do |col_idx|
          symbol = @position_map.symbol_at(:right, row_idx, col_idx)
          next unless symbol

          if overrides.key?(symbol)
            value = overrides[symbol]

            # 全行で逆順処理
            # row0-2: 5 - col_idx (6要素の場合)
            # row3: 2 - col_idx (3要素の場合)
            if row_idx == 3
              hardware_col_idx = 2 - col_idx
            else
              hardware_col_idx = 5 - col_idx
            end

            layer[row_idx + 4][hardware_col_idx] = resolve_to_qmk(value)
          end
        end
      end

      # 右手親指キー
      ['thumb_r_left', 'thumb_r_middle', 'thumb_r_right'].each_with_index do |symbol, idx|
        if overrides.key?(symbol)
          col_idx = 5 - idx  # 逆順
          layer[7][col_idx] = resolve_to_qmk(overrides[symbol])
        end
      end

      # 右手ロータリープッシュ (row1, col6)
      if overrides.key?('r_rotary_push')
        layer[5][6] = resolve_to_qmk(overrides['r_rotary_push'])
      end

      layer
    end

    def compile_encoders
      layer_files = Dir.glob("#{@config_dir}/layers/*.{yaml,yml}").sort_by do |file|
        File.basename(file).match(/^(\d+)_/)[1].to_i
      end

      encoders = Array.new(10) { [['KC_VOLD', 'KC_VOLU'], ['KC_WH_U', 'KC_WH_D']] }

      layer_files.each do |file|
        index = File.basename(file).match(/^(\d+)_/)[1].to_i
        layer_config = YAML.load_file(file)
        mapping = layer_config['mapping'] || layer_config['overrides'] || {}

        # 左エンコーダー
        if mapping['l_rotary_ccw'] && mapping['l_rotary_cw']
          encoders[index][0] = [
            resolve_to_qmk(mapping['l_rotary_ccw']),
            resolve_to_qmk(mapping['l_rotary_cw'])
          ]
        end

        # 右エンコーダー
        if mapping['r_rotary_ccw'] && mapping['r_rotary_cw']
          encoders[index][1] = [
            resolve_to_qmk(mapping['r_rotary_ccw']),
            resolve_to_qmk(mapping['r_rotary_cw'])
          ]
        end
      end

      encoders
    end

    def compile_macros
      macros = Array.new(32) { [] }

      Dir.glob("#{@config_dir}/macros/*.{yaml,yml}").each do |file|
        macro_config = YAML.load_file(file)
        next unless macro_config['enabled']

        # YAMLファイルからインデックスを取得
        index = macro_config['index']
        macros[index] = compile_macro_sequence(macro_config['sequence'])
      end

      macros
    end

    def compile_macro_sequence(sequence)
      result = []

      sequence.each do |step|
        action = step['action']
        case action
        when 'tap'
          keys = Array(step['keys'] || step['key']).map { |k| resolve_to_qmk(k) }
          result << ['tap'] + keys
        when 'down'
          keys = Array(step['keys'] || step['key']).map { |k| resolve_to_qmk(k) }
          result << ['down'] + keys
        when 'up'
          keys = Array(step['keys'] || step['key']).map { |k| resolve_to_qmk(k) }
          result << ['up'] + keys
        when 'text'
          result << ['text', step['content']]
        when 'delay'
          result << ['delay', step['duration']]
        end
      end

      result
    end

    def compile_tap_dance
      tap_dances = Array.new(32) { ['KC_NO', 'KC_NO', 'KC_NO', 'KC_NO', 250] }

      Dir.glob("#{@config_dir}/tap_dance/*.{yaml,yml}").each do |file|
        td_config = YAML.load_file(file)
        next unless td_config['enabled']

        # YAMLファイルからインデックスを取得
        index = td_config['index']
        actions = td_config['actions']
        tap_dances[index] = [
          resolve_to_qmk(actions['on_tap'] || 'KC_NO'),
          resolve_to_qmk(actions['on_hold'] || 'KC_NO'),
          resolve_to_qmk(actions['on_double_tap'] || 'KC_NO'),
          resolve_to_qmk(actions['on_tap_hold'] || 'KC_NO'),
          td_config['tapping_term'] || 250
        ]
      end

      tap_dances
    end

    def compile_combos
      combos = Array.new(32) { ['KC_NO', 'KC_NO', 'KC_NO', 'KC_NO', 'KC_NO'] }

      Dir.glob("#{@config_dir}/combos/*.{yaml,yml}").each do |file|
        combo_config = YAML.load_file(file)
        next unless combo_config['enabled']

        # YAMLファイルからインデックスを取得
        index = combo_config['index']
        triggers = combo_config['trigger']
        output = combo_config['output']

        combos[index] = [
          resolve_to_qmk(triggers[0] || 'KC_NO'),
          resolve_to_qmk(triggers[1] || 'KC_NO'),
          resolve_to_qmk(triggers[2] || 'KC_NO'),
          resolve_to_qmk(triggers[3] || 'KC_NO'),
          resolve_to_qmk(output)
        ]
      end

      combos
    end

    def compile_settings
      settings_file = "#{@config_dir}/settings/qmk_settings.yaml"
      return default_settings unless File.exist?(settings_file)

      qmk = YAML.load_file(settings_file)
      keyboard = qmk['keyboard'] || {}
      vial = qmk['vial'] || {}

      {
        '2' => vial['combo_timing_window'] || 50,
        '6' => 1000,
        '7' => keyboard['tapping_term'] || 250,
        '18' => keyboard['tap_code_delay'] || 20,
        '19' => keyboard['tap_hold_caps_delay'] || 20,
        '22' => keyboard['chordal_hold'] ? 1 : 0,
        '23' => 0,
        '26' => 1,
        '27' => keyboard['flow_tap'] || 120
      }
    end

    def default_settings
      {
        '2' => 50,
        '6' => 1000,
        '7' => 250,
        '18' => 20,
        '19' => 20,
        '22' => 1,
        '23' => 0,
        '26' => 1,
        '27' => 120
      }
    end

    def build_macro_index
      macro_files = Dir.glob("#{@config_dir}/macros/*.yaml").sort
      name_to_index = {}

      macro_files.each_with_index do |file, index|
        macro = YAML.load_file(file)
        name_to_index[macro['name']] = index
      end

      name_to_index
    end

    def empty_layer
      [
        [-1, -1, -1, -1, -1, -1, -1],
        [-1, -1, -1, -1, -1, -1, -1],
        [-1, -1, -1, -1, -1, -1, -1],
        [-1, -1, -1, -1, -1, -1, -1],
        [-1, -1, -1, -1, -1, -1, -1],
        [-1, -1, -1, -1, -1, -1, -1],
        [-1, -1, -1, -1, -1, -1, -1],
        [-1, -1, -1, -1, -1, -1, -1]
      ]
    end

    def deep_copy(obj)
      Marshal.load(Marshal.dump(obj))
    end

    def load_yaml(filename)
      YAML.load_file("#{@config_dir}/#{filename}")
    end
  end
end
