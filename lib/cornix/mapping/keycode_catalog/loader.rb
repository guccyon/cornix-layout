# frozen_string_literal: true

require 'yaml'
require_relative '../keycode_catalog'

module Cornix
  module Mapping
    class KeycodeCatalog
      # data/*.yaml を読んで KeycodeCatalog を組み立てる。表の不整合は ConfigError。
      class Loader
        MOD_FUNCS = {
          'LCTL' => 0x01, 'LSFT' => 0x02, 'LALT' => 0x04, 'LGUI' => 0x08,
          'RCTL' => 0x11, 'RSFT' => 0x12, 'RALT' => 0x14, 'RGUI' => 0x18
        }.freeze

        def initialize(data_dir: Cornix::DATA_DIR, custom_keycodes: [])
          @data_dir = data_dir
          @custom_keycodes = custom_keycodes
        end

        def load
          keycodes = read('keycodes.yaml')
          aliases = read('aliases.yaml')
          dangerous = read('dangerous_keycodes.yaml')
          unsupported = read('unsupported_keycodes.yaml')

          @qmk_names = {}
          @table_names = Hash.new { |h, k| h[k] = [] }
          @names_by_code = {}
          @vial_names = {}
          @basic = []
          @quantum = []
          %w[special basic shifted quantum].each do |section|
            Array(keycodes[section]).each { |entry| add_keycode(section, entry) }
          end
          add_custom_keycodes

          @aliases = {}
          @aliases_by_code = Hash.new { |h, k| h[k] = [] }
          %w[special basic quantum modified].each do |section|
            (aliases[section] || {}).each { |key, names| add_aliases(section, key, names) }
          end

          build(dangerous, unsupported)
        end

        private

        def read(file)
          path = File.join(@data_dir, file)
          text = File.read(path, encoding: 'UTF-8')
          reject_duplicate_keys!(Psych.parse(text, filename: path), path)
          YAML.safe_load(text, permitted_classes: [], aliases: false, filename: path)
        rescue Errno::ENOENT, Psych::Exception => e
          raise ConfigError.new(e.message, path: path)
        end

        def reject_duplicate_keys!(node, path)
          if node.is_a?(Psych::Nodes::Mapping)
            keys = node.children.each_slice(2).map { |key, _| key.respond_to?(:value) ? key.value : nil }.compact
            dup = keys.tally.find { |_, n| n > 1 }
            raise ConfigError.new("キー #{dup.first} が重複しています", path: path) if dup
          end
          Array(node.children).each { |child| reject_duplicate_keys!(child, path) }
        end

        def add_keycode(section, entry)
          code = entry.fetch('code')
          name = entry.fetch('name')
          register_name(name, code)
          Array(entry['qmk']).each { |q| register_name(q, code) }
          @table_names[code].push(name, *Array(entry['qmk']))
          return if section == 'shifted'

          raise ConfigError, "keycodes.yaml に値 #{format('0x%04X', code)} が 2 回あります" if @names_by_code.key?(code)

          @names_by_code[code] = name
          @vial_names[code] = name unless entry['vial'] == false
          (section == 'quantum' ? @quantum : @basic) << code unless section == 'special'
        end

        def add_custom_keycodes
          @custom_keycodes.each_with_index do |custom, i|
            name = custom.is_a?(Hash) ? custom['name'] : custom
            next if name.nil? || name.empty?

            code = @qmk_names.fetch(format('USER%02d', i)) { raise ConfigError, "USER#{i} がありません" }
            register_name(name, code)
          end
        end

        def register_name(name, code)
          prev = @qmk_names[name]
          raise ConfigError, "名前 #{name} が 2 つの値に割り当てられています" if prev && prev != code

          @qmk_names[name] = code
        end

        def add_aliases(section, key, names)
          code = section == 'modified' ? modified_code(key) : @qmk_names[key]
          raise ConfigError, "aliases.yaml の #{key} は keycodes.yaml にありません" unless code
          raise ConfigError, "aliases.yaml の #{key} の別名が空です" if !names.is_a?(Array) || names.empty?
          raise ConfigError, "aliases.yaml で #{key} の値が 2 回定義されています" if @aliases_by_code.key?(code)

          names.each do |name|
            name = name.to_s
            # customKeycodes の名前と同じ別名は、同じ値を指していれば許す
            if @aliases.key?(name) || (@qmk_names.key?(name) && @qmk_names[name] != code)
              raise ConfigError, "別名 #{name} が重複しています（#{key}）"
            end

            @aliases[name] = code
            @aliases_by_code[code] << name
          end
        end

        # "LSFT(KC_1)" のような単一の修飾関数 → 値
        def modified_code(key)
          m = key.match(/\A([A-Z]{4})\((\w+)\)\z/) or raise ConfigError, "modified のキーが不正です: #{key}"
          bits = MOD_FUNCS[m[1]] or raise ConfigError, "modified の修飾関数が不明です: #{key}"
          base = @qmk_names[m[2]] or raise ConfigError, "modified の #{m[2]} は keycodes.yaml にありません"
          raise ConfigError, "modified の #{m[2]} は基本キーではありません" unless base.between?(0x04, 0xFF)

          (bits << 8) | base
        end

        def build(dangerous, unsupported)
          KeycodeCatalog.new(
            qmk_names: @qmk_names, table_names: @table_names.transform_values(&:freeze).to_h,
            names_by_code: @names_by_code, vial_names: @vial_names, aliases: @aliases,
            aliases_by_code: @aliases_by_code.transform_values(&:freeze).to_h,
            preferred: @aliases_by_code.transform_values(&:first).to_h,
            basic: @basic.to_set, quantum: @quantum.to_set,
            dangerous_ranges: ranges(dangerous, '書き込み禁止のキー'),
            unsupported_ranges: ranges(unsupported, 'Cornix では使えないキー')
          )
        end

        # { ranges: [{ from:, to:, reason: }] } → [[Range, 理由]]
        def ranges(table, default_reason)
          Array(table['ranges']).map { |r| [(r.fetch('from')..r.fetch('to')), r['reason'] || default_reason] }
        end
      end
    end
  end
end
