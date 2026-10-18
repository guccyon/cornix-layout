# frozen_string_literal: true

require 'yaml'

module Cornix
  module Mapping
    # 同梱のショートカット（data/shortcuts/*.yaml。cornixhub で共有されているもの）。
    # ファイルは「アプリ → カテゴリ → ラベル: キーコードの表記」の入れ子で、名前はキーを ':' でつないだもの
    # （Shortcut('Spotify:再生:次のクリップ')）。キーに ':' は使えない。
    #
    #   ShortcutCatalog.default                 同梱の表（プロセスで 1 回だけ読む）
    #   catalog.texts                           名前 => キーコードの表記（ファイル名順・定義順）
    #   catalog.library(notation)               Domain::ShortcutLibrary（直前と同じ notation なら解析し直さない）
    #
    # 同梱データの誤り（形・名前の重複・解釈できない表記）は ConfigError
    class ShortcutCatalog
      SEPARATOR = ':'
      DIR = File.join(Cornix::DATA_DIR, 'shortcuts')

      def self.default = @default ||= load

      def self.load(dir = DIR)
        texts = {}
        paths = {}
        Dir[File.join(dir, '*.{yaml,yml}')].sort.each do |path|
          flatten(read(path), [], path, texts, paths)
        end
        new(texts, paths)
      end

      def self.read(path)
        YAML.safe_load_file(path)
      rescue Psych::Exception => e
        raise ConfigError.new(e.message, path: path)
      end

      def self.flatten(node, keys, path, texts, paths)
        where = keys.empty? ? 'ファイルの先頭' : keys.join(SEPARATOR)
        raise ConfigError.new("#{where} は空でない Hash にしてください", path: path) unless node.is_a?(Hash) && !node.empty?

        node.each do |key, value|
          unless key.is_a?(String) && !key.strip.empty? && !key.include?(SEPARATOR)
            raise ConfigError.new("名前は ':' を含まない空でない文字列にしてください: #{key.inspect}", path: path)
          end

          names = keys + [key.strip]
          next flatten(value, names, path, texts, paths) if value.is_a?(Hash)

          name = names.join(SEPARATOR)
          raise ConfigError.new("「#{name}」の値はキーコードの表記（文字列）にしてください", path: path) unless value.is_a?(String)
          raise ConfigError.new("ショートカット「#{name}」が重複しています", path: path) if texts.key?(name)

          texts[name] = value
          paths[name] = path
        end
      end
      private_class_method :read, :flatten

      attr_reader :texts

      # paths は名前 => 定義のあるファイル（エラーの場所に使う）
      def initialize(texts = {}, paths = {})
        @texts = texts.dup.freeze
        @paths = paths.dup.freeze
        @library = nil
      end

      def library(notation)
        return @library.last if @library&.first.equal?(notation)

        library = Domain::ShortcutLibrary.new(entries: @texts.to_h { |name, text| [name, parse(notation, name, text)] })
        @library = [notation, library]
        library
      end

      private

      def parse(notation, name, text)
        notation.parse(text)
      rescue UnknownKeycode => e
        raise ConfigError.new("ショートカット「#{name}」: #{e.message}", path: @paths[name])
      end
    end
  end
end
