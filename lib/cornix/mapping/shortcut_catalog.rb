# frozen_string_literal: true

require 'yaml'

module Cornix
  module Mapping
    # 同梱のショートカット（data/shortcuts/*.yaml。cornixhub で共有されているもの）。
    # ファイルは「アプリ → カテゴリ → ラベル: 定義」の入れ子で、名前はキーを ':' でつないだもの
    # （Shortcut('Spotify:再生:次のクリップ')）。キーに ':' は使えない。定義は 2 種類:
    #
    #   次のクリップ: Command + Right            1 シーケンス（キーコードの表記）。Shortcut('名前') でも preset: でも使える
    #   スプライン:                              複数の手順（マクロ）。macros/ の preset: でだけ使える
    #     macro:                                 macros/ の sequence と同じ形（action は tap / down / up だけ）
    #       - { action: tap, keys: S }
    #       - { action: tap, keys: P }
    #
    #   ShortcutCatalog.default                 同梱の表（プロセスで 1 回だけ読む）
    #   catalog.texts                           1 シーケンスの名前 => キーコードの表記（ファイル名順・定義順）
    #   catalog.macro_names                     マクロの定義の名前
    #   catalog.preset_names                    preset: に書ける名前（1 シーケンスとマクロの定義のすべて）
    #   catalog.library(notation)               1 シーケンスの Domain::ShortcutLibrary（直前と同じ notation なら解析し直さない）
    #   catalog.preset(name, notation)          macros/ の preset: の手順（[Domain::MacroStep]）。なければ nil
    #
    # 同梱データの誤り（形・名前の重複・解釈できない表記）は ConfigError
    class ShortcutCatalog
      SEPARATOR = ':'
      DIR = File.join(Cornix::DATA_DIR, 'shortcuts')
      MACRO_KEY = 'macro'
      STEP_KEYS = %w[action keys].freeze
      STEP_ACTIONS = Domain::MacroStep::KEY_ACTIONS

      # 修飾キー（Domain::ModifierSet の名前）→ 左側の修飾キーの基本キーの値（右側は + 4）
      MODIFIER_CODES = { ctrl: 0xE0, shift: 0xE1, alt: 0xE2, gui: 0xE3 }.freeze
      RIGHT_OFFSET = 4

      def self.default = @default ||= load

      def self.load(dir = DIR)
        entries = { texts: {}, macros: {}, paths: {} }
        Dir[File.join(dir, '*.{yaml,yml}')].sort.each do |path|
          flatten(read(path), [], path, entries)
        end
        new(entries[:texts], entries[:paths], entries[:macros])
      end

      def self.read(path)
        YAML.safe_load_file(path)
      rescue Psych::Exception => e
        raise ConfigError.new(e.message, path: path)
      end

      def self.flatten(node, keys, path, entries)
        where = keys.empty? ? 'ファイルの先頭' : keys.join(SEPARATOR)
        raise ConfigError.new("#{where} は空でない Hash にしてください", path: path) unless node.is_a?(Hash) && !node.empty?

        node.each do |key, value|
          unless key.is_a?(String) && !key.strip.empty? && !key.include?(SEPARATOR)
            raise ConfigError.new("名前は ':' を含まない空でない文字列にしてください: #{key.inspect}", path: path)
          end

          names = keys + [key.strip]
          next flatten(value, names, path, entries) if value.is_a?(Hash) && !macro?(value)

          add(names.join(SEPARATOR), value, path, entries)
        end
      end

      def self.add(name, value, path, entries)
        if entries[:paths].key?(name)
          raise ConfigError.new("ショートカット「#{name}」が重複しています", path: path)
        end

        if macro?(value)
          entries[:macros][name] = check_steps(name, value[MACRO_KEY], path)
        elsif value.is_a?(String)
          entries[:texts][name] = value
        else
          raise ConfigError.new("「#{name}」の値はキーコードの表記（文字列）か { macro: [...] } にしてください", path: path)
        end
        entries[:paths][name] = path
      end

      # { macro: ... } だけの Hash はマクロの定義（カテゴリではない）
      def self.macro?(value) = value.is_a?(Hash) && value.keys == [MACRO_KEY]

      # 手順の形（[{ action: tap / down / up, keys: 表記 または [表記, ...] }, ...]）を確かめる。表記の解釈は preset で行う
      def self.check_steps(name, steps, path)
        unless steps.is_a?(Array) && !steps.empty?
          raise ConfigError.new("「#{name}」の macro は手順の空でないリストにしてください", path: path)
        end

        steps.each_with_index do |step, i|
          keys = step.is_a?(Hash) && step['keys']
          valid = step.is_a?(Hash) && step.keys.sort == STEP_KEYS.sort && STEP_ACTIONS.key?(step['action']) &&
                  (keys.is_a?(String) || (keys.is_a?(Array) && !keys.empty? && keys.all?(String)))
          next if valid

          raise ConfigError.new("「#{name}」の macro[#{i}] は { action: tap / down / up, keys: キー } にしてください: " \
                                "#{step.inspect}", path: path)
        end
        steps
      end
      private_class_method :read, :flatten, :add, :macro?, :check_steps

      attr_reader :texts

      # texts は 1 シーケンスの名前 => 表記、paths は名前 => 定義のあるファイル（エラーの場所に使う）、
      # macros はマクロの名前 => 手順（data/shortcuts/ の macro: の値）
      def initialize(texts = {}, paths = {}, macros = {})
        @texts = texts.dup.freeze
        @paths = paths.dup.freeze
        @macros = macros.dup.freeze
        @library = nil
        @presets = nil
      end

      def macro_names = @macros.keys

      # preset: に書ける名前（1 シーケンスとマクロの定義のすべて）
      def preset_names = @texts.keys + @macros.keys

      def library(notation)
        return @library.last if @library&.first.equal?(notation)

        library = Domain::ShortcutLibrary.new(entries: @texts.to_h { |name, text| [name, parse(notation, name, text)] })
        @library = [notation, library]
        library
      end

      # macros/ の preset: に書いた名前の手順。マクロの定義はその手順、1 シーケンスの定義は
      # 押して離す手順（修飾キー付きは「修飾キーを押す → キーを押して離す → 修飾キーを離す」）。どちらにもなければ nil
      def preset(name, notation)
        @presets = [notation, {}] unless @presets&.first.equal?(notation)
        cache = @presets.last
        return cache[name] if cache.key?(name)

        cache[name] =
          if @macros.key?(name) then macro_steps(notation, name)
          elsif @texts.key?(name) then key_steps(library(notation).entries.fetch(name))
          end
      end

      private

      def parse(notation, name, text)
        notation.parse(text)
      rescue UnknownKeycode => e
        raise ConfigError.new("ショートカット「#{name}」: #{e.message}", path: @paths[name])
      end

      def macro_steps(notation, name)
        @macros[name].map do |step|
          keys = Array(step['keys']).map { |text| parse(notation, name, text) }
          STEP_ACTIONS.fetch(step['action']).new(keys: keys)
        end
      rescue InvalidValue => e
        raise ConfigError.new("ショートカット「#{name}」: #{e.message}", path: @paths[name])
      end

      def key_steps(keycode)
        return [Domain::MacroStep::Tap.new(keys: [keycode])] unless keycode.is_a?(Domain::Keycode::Modified)

        offset = keycode.mods.right? ? RIGHT_OFFSET : 0
        mods = keycode.mods.mods.map { |m| Domain::Keycode::Basic.new(code: MODIFIER_CODES.fetch(m) + offset) }
        [Domain::MacroStep::Down.new(keys: mods), Domain::MacroStep::Tap.new(keys: [keycode.base]),
         Domain::MacroStep::Up.new(keys: mods.reverse)]
      end
    end
  end
end
