# frozen_string_literal: true

require 'json'
require 'yaml'
require_relative 'keycode_resolver'
require_relative 'keycode_parser'
require_relative 'reference_resolver'

module Cornix
  # layout.vilをYAML設定ファイルに変換するデコンパイラ
  class Decompiler
    def initialize(vil_path)
      @vil_path = vil_path
      @data = JSON.parse(File.read(vil_path))

      # KeycodeResolverを初期化（エイリアス変換用）
      aliases_path = File.join(__dir__, 'keycode_aliases.yaml')
      @keycode_resolver = KeycodeResolver.new(aliases_path)

      # Load position map template
      @position_map_template_path = File.join(__dir__, 'position_map.yaml')
      unless File.exist?(@position_map_template_path)
        raise "Missing required template: #{@position_map_template_path}"
      end
      @position_map_template = YAML.load_file(@position_map_template_path)
    end

    def decompile(output_dir)
      FileUtils.mkdir_p(output_dir)

      extract_metadata(output_dir)
      extract_position_map(output_dir)
      extract_qmk_settings(output_dir)

      # Extract macros, tap dance, and combos first
      # so ReferenceResolver can find them
      extract_macros(output_dir)
      extract_tap_dance(output_dir)
      extract_combos(output_dir)

      # Initialize ReferenceResolver after files are created
      @reference_resolver = ReferenceResolver.new(output_dir)

      # Extract layers last, so they can use name-based references
      extract_layers(output_dir)

      puts "✓ Decompilation completed: #{output_dir}"
    end

    private

    # QMKキーコードをエイリアスに変換
    def resolve_to_alias(keycode)
      return keycode if keycode.nil? || keycode == '' || keycode == -1

      # Parse using KeycodeParser
      parsed = KeycodeParser.parse(keycode)

      case parsed[:type]
      when :keycode
        # QMK keycode → alias
        @keycode_resolver.reverse_resolve(parsed[:value])

      when :legacy_macro
        # M0 → Macro('End of Line') or Macro(0) (fallback)
        if @reference_resolver
          token = @reference_resolver.reverse_resolve(parsed[:value], prefer_name: true)
          KeycodeParser.unparse(token)
        else
          parsed[:value]
        end

      when :legacy_tap_dance
        # TD(2) → TapDance('Escape') or TapDance(2) (fallback)
        if @reference_resolver
          token = @reference_resolver.reverse_resolve(parsed[:value], prefer_name: true)
          KeycodeParser.unparse(token)
        else
          parsed[:value]
        end

      when :function
        # Process function arguments recursively
        function_name = parsed[:name]
        args = parsed[:args]

        resolved_args = args.map do |arg|
          resolved = resolve_to_alias(KeycodeParser.unparse(arg))
          KeycodeParser.parse(resolved)
        end

        token = { type: :function, name: function_name, args: resolved_args }
        KeycodeParser.unparse(token)

      else
        # Unknown - return as-is
        parsed[:value] || keycode
      end
    end

    def extract_metadata(output_dir)
      metadata = {
        'keyboard' => 'cornix',
        'version' => @data['version'],
        'uid' => @data['uid'],
        'vial_protocol' => @data['vial_protocol'],
        'via_protocol' => @data['via_protocol'],
        'layout_options' => @data['layout_options'],
        'file_naming' => {
          'layers' => {
            'pattern' => '{index}_{name}.yaml',
            'index_required' => true,
            'index_range' => [0, 9]
          },
          'macros' => {
            'pattern' => '{name}.yaml',
            'name_required' => true
          },
          'tap_dance' => {
            'pattern' => '{name}.yaml',
            'name_required' => true
          },
          'combos' => {
            'pattern' => '{name}.yaml',
            'name_required' => true
          }
        },
        'references' => {
          'macros' => {
            'preferred' => 'MACRO(name)',
            'legacy' => 'MACRO(index)'
          },
          'tap_dance' => {
            'preferred' => 'TD(name)',
            'legacy' => 'TD(index)'
          },
          'layers' => {
            'syntax' => 'MO(index), LT(index, key), ...'
          }
        }
      }

      write_yaml("#{output_dir}/metadata.yaml", metadata)
    end

    def extract_position_map(output_dir)
      # Generate config/position_map.yaml from template
      write_yaml_with_flow_arrays("#{output_dir}/position_map.yaml", @position_map_template)
    end

    def extract_qmk_settings(output_dir)
      settings_data = @data['settings'] || {}

      qmk_settings = {
        'keyboard' => {
          'tapping_term' => settings_data['7'] || 250,
          'permissive_hold' => false,
          'hold_on_other_key_press' => false,
          'tap_code_delay' => settings_data['18'] || 20,
          'tap_hold_caps_delay' => settings_data['19'] || 20,
          'chordal_hold' => settings_data['22'] == 1,
          'flow_tap' => settings_data['27'] || 120
        },
        'vial' => {
          'combo_timing_window' => settings_data['2'] || 50
        }
      }

      FileUtils.mkdir_p("#{output_dir}/settings")
      write_yaml("#{output_dir}/settings/qmk_settings.yaml", qmk_settings)
    end

    def extract_layers(output_dir)
      layers_dir = "#{output_dir}/layers"
      FileUtils.mkdir_p(layers_dir)

      @data['layout'].each_with_index do |layer_data, index|
        extract_layer(layers_dir, index, layer_data,
                     @data['encoder_layout'][index])
      end
    end

    def extract_layer(dir, index, layer_data, encoder_data)
      # レイヤー0は完全な定義、それ以外は差分のみ
      if index == 0
        extract_base_layer(dir, layer_data, encoder_data)
      else
        extract_override_layer(dir, index, layer_data, encoder_data)
      end
    end

    def extract_base_layer(dir, layer_data, encoder_data)
      mapping = {}

      # 左手
      ['row0', 'row1', 'row2', 'row3'].each_with_index do |row_key, row_idx|
        row = @position_map_template['left_hand'][row_key]
        row.each_with_index do |symbol, col_idx|
          next if symbol.nil? || symbol.to_s.empty?
          keycode = layer_data[row_idx][col_idx]
          mapping[symbol] = resolve_to_alias(keycode) unless keycode == -1
        end
      end

      # 右手
      # Cornixの右手側は物理的に右から左にインデックスが振られているため、列を逆転
      # row3も含めて全行で逆順処理を適用
      ['row0', 'row1', 'row2', 'row3'].each_with_index do |row_key, row_idx|
        row = @position_map_template['right_hand'][row_key]
        row.each_with_index do |symbol, col_idx|
          next if symbol.nil? || symbol.to_s.empty?

          # 全行で逆順: position_mapの左から右の順序を、ハードウェアの右から左に変換
          # ただし、row3は3要素しかないため、5 - col_idxではなく、(row.size - 1) - col_idxを使用
          hardware_col_idx = (row.size - 1) - col_idx

          keycode = layer_data[row_idx + 4][hardware_col_idx]
          mapping[symbol] = resolve_to_alias(keycode) unless keycode == -1
        end
      end

      # エンコーダー
      mapping['l_rotary_push'] = resolve_to_alias(layer_data[2][6])  # Row 2, Col 6
      mapping['l_rotary_ccw'] = resolve_to_alias(encoder_data[0][0])
      mapping['l_rotary_cw'] = resolve_to_alias(encoder_data[0][1])
      mapping['r_rotary_push'] = resolve_to_alias(layer_data[5][6])  # Row 5, Col 6
      mapping['r_rotary_ccw'] = resolve_to_alias(encoder_data[1][0])
      mapping['r_rotary_cw'] = resolve_to_alias(encoder_data[1][1])

      # 親指キー
      # 左手親指キー（Row 3, Cols 3-5）
      @position_map_template['thumb_keys']['left'].each_with_index do |symbol, idx|
        col_idx = 3 + idx
        keycode = layer_data[3][col_idx]
        mapping[symbol] = resolve_to_alias(keycode) unless keycode == -1
      end

      # 右手親指キー（Row 7, Cols 5-3 逆順）
      @position_map_template['thumb_keys']['right'].each_with_index do |symbol, idx|
        col_idx = 5 - idx  # 逆順: 5, 4, 3
        keycode = layer_data[7][col_idx]
        mapping[symbol] = resolve_to_alias(keycode) unless keycode == -1
      end

      layer = {
        'name' => 'Layer 0',
        'description' => 'Base layer',
        'mapping' => mapping
      }

      write_yaml("#{dir}/0_layer.yml", layer)
    end

    def extract_override_layer(dir, index, layer_data, encoder_data)
      overrides = {}
      base_layer = @data['layout'][0]

      # 左手
      ['row0', 'row1', 'row2', 'row3'].each_with_index do |row_key, row_idx|
        row = @position_map_template['left_hand'][row_key]
        row.each_with_index do |symbol, col_idx|
          next if symbol.nil? || symbol.to_s.empty?
          keycode = layer_data[row_idx][col_idx]
          base_keycode = base_layer[row_idx][col_idx]

          # 差分のみ記録（-1は除外、KC_TRNSは含める）
          if keycode != base_keycode && keycode != -1
            overrides[symbol] = resolve_to_alias(keycode)
          end
        end
      end

      # 右手
      # Cornixの右手側は物理的に右から左にインデックスが振られているため、列を逆転
      # row3も含めて全行で逆順処理を適用
      ['row0', 'row1', 'row2', 'row3'].each_with_index do |row_key, row_idx|
        row = @position_map_template['right_hand'][row_key]
        row.each_with_index do |symbol, col_idx|
          next if symbol.nil? || symbol.to_s.empty?

          # 全行で逆順: position_mapの左から右の順序を、ハードウェアの右から左に変換
          # ただし、row3は3要素しかないため、5 - col_idxではなく、(row.size - 1) - col_idxを使用
          hardware_col_idx = (row.size - 1) - col_idx

          keycode = layer_data[row_idx + 4][hardware_col_idx]
          base_keycode = base_layer[row_idx + 4][hardware_col_idx]

          if keycode != base_keycode && keycode != -1
            overrides[symbol] = resolve_to_alias(keycode)
          end
        end
      end

      # エンコーダーの差分
      base_encoder = @data['encoder_layout'][0]

      # エンコーダープッシュボタンの差分をチェック
      l_push_keycode = layer_data[2][6]
      l_push_base = base_layer[2][6]
      if l_push_keycode != l_push_base && l_push_keycode != -1
        overrides['l_rotary_push'] = resolve_to_alias(l_push_keycode)
      end

      r_push_keycode = layer_data[5][6]
      r_push_base = base_layer[5][6]
      if r_push_keycode != r_push_base && r_push_keycode != -1
        overrides['r_rotary_push'] = resolve_to_alias(r_push_keycode)
      end

      # エンコーダー回転の差分をチェック
      if encoder_data[0] != base_encoder[0]
        overrides['l_rotary_ccw'] = resolve_to_alias(encoder_data[0][0])
        overrides['l_rotary_cw'] = resolve_to_alias(encoder_data[0][1])
      end
      if encoder_data[1] != base_encoder[1]
        overrides['r_rotary_ccw'] = resolve_to_alias(encoder_data[1][0])
        overrides['r_rotary_cw'] = resolve_to_alias(encoder_data[1][1])
      end

      # 親指キーの差分をチェック
      # 左手親指キー
      @position_map_template['thumb_keys']['left'].each_with_index do |symbol, idx|
        col_idx = 3 + idx
        keycode = layer_data[3][col_idx]
        base_keycode = base_layer[3][col_idx]
        if keycode != base_keycode && keycode != -1
          overrides[symbol] = resolve_to_alias(keycode)
        end
      end

      # 右手親指キー
      @position_map_template['thumb_keys']['right'].each_with_index do |symbol, idx|
        col_idx = 5 - idx  # 逆順
        keycode = layer_data[7][col_idx]
        base_keycode = base_layer[7][col_idx]
        if keycode != base_keycode && keycode != -1
          overrides[symbol] = resolve_to_alias(keycode)
        end
      end

      return if overrides.empty?  # 空のレイヤーはスキップ

      layer = {
        'name' => "Layer #{index}",
        'description' => "Layer #{index}",
        'overrides' => overrides
      }

      write_yaml("#{dir}/#{index}_layer.yml", layer)
    end

    def extract_macros(output_dir)
      macros_dir = "#{output_dir}/macros"
      FileUtils.mkdir_p(macros_dir)

      @data['macro'].each_with_index do |macro_data, index|
        next if macro_data.nil? || macro_data.empty?
        extract_macro(macros_dir, index, macro_data)
      end
    end

    def extract_macro(dir, index, macro_data)
      sequence = []
      macro_data.each do |step|
        action = step[0]
        keys = step[1..-1]

        case action
        when 'tap'
          sequence << {
            'action' => 'tap',
            'keys' => keys
          }
        when 'down'
          sequence << {
            'action' => 'down',
            'keys' => keys.length == 1 ? keys[0] : keys
          }
        when 'up'
          sequence << {
            'action' => 'up',
            'keys' => keys.length == 1 ? keys[0] : keys
          }
        when 'text'
          sequence << {
            'action' => 'text',
            'content' => keys[0]
          }
        end
      end

      macro = {
        'name' => "Macro #{index}",
        'description' => "Macro #{index}",
        'enabled' => true,
        'index' => index,  # YAMLにインデックスを保存
        'sequence' => sequence
      }

      filename = "%02d_macro.yml" % index
      write_yaml("#{dir}/#{filename}", macro)
    end

    def extract_tap_dance(output_dir)
      td_dir = "#{output_dir}/tap_dance"
      FileUtils.mkdir_p(td_dir)

      @data['tap_dance'].each_with_index do |td_data, index|
        next if td_data[0] == 'KC_NO' && td_data[1] == 'KC_NO'
        extract_tap_dance_item(td_dir, index, td_data)
      end
    end

    def extract_tap_dance_item(dir, index, td_data)
      tap_dance = {
        'name' => "Tap Dance #{index}",
        'description' => "Tap Dance #{index}",
        'enabled' => true,
        'index' => index,  # YAMLにインデックスを保存
        'actions' => {
          'on_tap' => td_data[0],
          'on_hold' => td_data[1],
          'on_double_tap' => td_data[2],
          'on_tap_hold' => td_data[3]
        },
        'tapping_term' => td_data[4]
      }

      filename = "%02d_tap_dance.yml" % index
      write_yaml("#{dir}/#{filename}", tap_dance)
    end

    def extract_combos(output_dir)
      combos_dir = "#{output_dir}/combos"
      FileUtils.mkdir_p(combos_dir)

      @data['combo'].each_with_index do |combo_data, index|
        next if combo_data[0] == 'KC_NO'
        extract_combo(combos_dir, index, combo_data)
      end
    end

    def extract_combo(dir, index, combo_data)
      # トリガーキーを取得
      triggers = [combo_data[0], combo_data[1]].compact.reject { |k| k == 'KC_NO' }
      output = combo_data[4]

      combo = {
        'name' => "Combo #{index}",
        'description' => "#{triggers.join(' + ')} → #{output}",
        'enabled' => true,
        'index' => index,  # YAMLにインデックスを保存
        'trigger' => triggers,
        'output' => output
      }

      filename = "%02d_combo.yml" % index
      write_yaml("#{dir}/#{filename}", combo)
    end

    def write_yaml(path, data)
      File.write(path, YAML.dump(data))
      puts "  Created: #{path}"
    end

    def write_yaml_with_flow_arrays(path, data)
      # position_map用の特殊フォーマット
      yaml_lines = ["---"]

      # left_hand
      yaml_lines << "left_hand:"
      if data['left_hand'].is_a?(Hash)
        data['left_hand'].each do |row_key, row_data|
          if row_data.is_a?(Array)
            yaml_lines << "  #{row_key}: [#{row_data.join(', ')}]"
          else
            yaml_lines << "  #{row_key}: #{row_data}"
          end
        end
      end

      # right_hand
      yaml_lines << "right_hand:"
      if data['right_hand'].is_a?(Hash)
        data['right_hand'].each do |row_key, row_data|
          if row_data.is_a?(Array)
            yaml_lines << "  #{row_key}: [#{row_data.join(', ')}]"
          else
            yaml_lines << "  #{row_key}: #{row_data}"
          end
        end
      end

      # thumb_keys
      yaml_lines << "thumb_keys:"
      if data['thumb_keys'].is_a?(Hash)
        data['thumb_keys'].each do |side, keys|
          yaml_lines << "  #{side}: [#{keys.join(', ')}]"
        end
      end

      # encoders
      yaml_lines << "encoders:"
      if data['encoders'].is_a?(Hash)
        data['encoders'].each do |side, encoder_data|
          yaml_lines << "  #{side}:"
          encoder_data.each do |key, value|
            yaml_lines << "    #{key}: #{value}"
          end
        end
      end

      File.write(path, yaml_lines.join("\n") + "\n")
      puts "  Created: #{path}"
    end

    def format_arrays_as_flow(yaml_str)
      lines = yaml_str.split("\n")
      result = []
      i = 0

      while i < lines.size
        line = lines[i]

        # この行がキーで、次の行が配列かチェック
        # row0: のような行を探す
        if line =~ /^(\s*)([a-zA-Z_]\w*):\s*$/ && i + 1 < lines.size && lines[i + 1] =~ /^\s*-/
          indent = $1
          key = $2

          # 配列要素を収集
          items = []
          j = i + 1
          array_indent = nil

          while j < lines.size
            if lines[j] =~ /^(\s*)-\s+(.+)$/
              array_indent ||= $1
              # 同じインデントレベルの配列要素のみを収集
              if $1 == array_indent
                items << $2
                j += 1
              else
                break
              end
            else
              break
            end
          end

          # flow形式で出力
          if items.any?
            result << "#{indent}#{key}: [#{items.join(', ')}]"
            i = j
          else
            result << line
            i += 1
          end
        else
          result << line
          i += 1
        end
      end

      result.join("\n")
    end
  end
end
