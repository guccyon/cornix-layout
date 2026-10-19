# frozen_string_literal: true

require 'yaml'

module Cornix
  module Mapping
    # 同梱のショートカットのアプリ名 → アイコン ID の表（data/shortcut_icons.yaml）。
    # ID は "simple-icons:<slug>" / "material-icon-theme:<name>" / "badge:<文字>" のどれか（画像は拡張に同梱）
    #
    #   AppIconCatalog.default               同梱の表（プロセスで 1 回だけ読む）
    #   catalog.icon('Figma')                #=> "simple-icons:figma"。表にないアプリ（自分のショートカットなど）は nil
    #   catalog.app_names                    表にあるアプリ名（ファイルの順）
    #
    # 表の誤り（形・ID の書き方）は ConfigError
    class AppIconCatalog
      PATH = File.join(Cornix::DATA_DIR, 'shortcut_icons.yaml')
      ID_PATTERN = /\A(?:simple-icons:[a-z0-9_]+|material-icon-theme:[a-z0-9_-]+|badge:[A-Za-z0-9]{1,3})\z/

      def self.default = @default ||= load

      def self.load(path = PATH)
        data = YAML.safe_load_file(path)
        icons = data['icons'] if data.is_a?(Hash)
        raise ConfigError.new('icons: にアプリ名 → アイコン ID の Hash を書いてください', path: path) unless icons.is_a?(Hash)

        icons.each do |name, id|
          next if name.is_a?(String) && id.is_a?(String) && ID_PATTERN.match?(id)

          raise ConfigError.new("「#{name}」のアイコン ID が正しくありません: #{id.inspect}", path: path)
        end
        new(icons)
      rescue Errno::ENOENT, Psych::Exception => e
        raise ConfigError.new(e.message, path: path)
      end

      def initialize(icons)
        @icons = icons.dup.freeze
        freeze
      end

      def icon(app_name) = @icons[app_name]

      def app_names = @icons.keys
    end
  end
end
