# frozen_string_literal: true

require 'json'
require 'yaml'
require_relative 'keycode_resolver'
require_relative 'position_map'

module Cornix
  # YAML設定ファイルをlayout.vilに変換するコンパイラ
  class Compiler
    def initialize(config_dir)
      @config_dir = config_dir
      # lib/cornix/keycode_aliases.yaml を直接参照
      aliases_path = File.join(__dir__, 'keycode_aliases.yaml')
      @keycode_resolver = KeycodeResolver.new(aliases_path)
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

      # パターン1: 既にQMK形式（KC_*）の場合はそのまま
      return keycode if keycode.match?(/^KC_[A-Z0-9_]+$/)

      # パターン2: 関数呼び出し形式（LSFT(1), LGUI_T(A)など）
      if match = keycode.match(/^([A-Z_]+[0-9]*)\((.+)\)$/)
        function_name = match[1]
        arguments = match[2]

        # 引数をカンマで分割（LT(1, Space)のようなケース）
        args = arguments.split(',').map(&:strip)
        resolved_args = args.map do |arg|
          # 引数が数値のみの場合、レイヤー切り替え系・タップダンス（MO, TO, OSL, TG, LT, TT, TD）なら数値のまま
          # それ以外（LSFT, LCTLなど）は KC_* に変換
          if arg.match?(/^\d+$/)
            # レイヤー切り替え系・タップダンス・コンボの関数かチェック
            if function_name.match?(/^(MO|TO|OSL|TG|TT|DF|LT\d*|TD|COMBO)$/)
              arg  # インデックス番号はそのまま
            else
              # 修飾キー系の関数の場合、KC_0-9 に変換
              "KC_#{arg}"
            end
          else
            resolve_to_qmk(arg)
          end
        end

        return "#{function_name}(#{resolved_args.join(', ')})"
      end

      # パターン3: 単独の数値（'1', '2'など）→ KC_1, KC_2
      if keycode.match?(/^[0-9]$/)
        return "KC_#{keycode}"
      end

      # パターン4: エイリアスとして登録されている場合、QMKキーコードに変換
      resolved = @keycode_resolver.resolve(keycode)
      return resolved if resolved != keycode

      # パターン5: マクロ参照（M0, M1など）、特殊な文字列はそのまま
      keycode
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
      4.times do |row_idx|
        6.times do |col_idx|
          symbol = @position_map.symbol_at(:right, row_idx, col_idx)
          next unless symbol

          keycode = mapping[symbol]
          # position_mapの左から右の順序を、ハードウェアの右から左に変換
          hardware_col_idx = 5 - col_idx
          layer[row_idx + 4][hardware_col_idx] = resolve_to_qmk(keycode || 'KC_NO')
        end
      end

      # 右手ロータリープッシュ (row1, col6)
      layer[5][6] = resolve_to_qmk(mapping['r_rotary_push']) if mapping['r_rotary_push']
      layer[5][6] ||= -1

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

      # 右手（通常キー）
      # Cornixの右手側は物理的に右から左にインデックスが振られているため、列を逆転
      4.times do |row_idx|
        6.times do |col_idx|
          symbol = @position_map.symbol_at(:right, row_idx, col_idx)
          next unless symbol

          if overrides.key?(symbol)
            value = overrides[symbol]
            # position_mapの左から右の順序を、ハードウェアの右から左に変換
            hardware_col_idx = 5 - col_idx
            layer[row_idx + 4][hardware_col_idx] = resolve_to_qmk(value)
          end
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
