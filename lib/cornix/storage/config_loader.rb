# frozen_string_literal: true

require_relative 'problems'
require_relative 'yaml_file'
require_relative 'config_files'

module Cornix
  module Storage
    # 設定ディレクトリを読んで Domain::Profile を作る（ConfigRepository#load の中身）。
    #
    # 読む順: metadata → position_map → macros → tap_dance → shortcuts（ここで Macro('名前') / TapDance('名前') /
    # Shortcut('名前') の対応表 Mapping::References を作る。Shortcut('名前') は shortcuts.yaml になければ同梱の
    # ショートカット（Mapping::ShortcutCatalog）を引く）→ settings → layers → combos。
    # キーコードの文字列は KeycodeNotation#parse で 1 回だけ解析する。
    # 問題はすべて集めて最後に 1 つの InvalidConfig にする（「ファイル: キーの位置: 内容」）
    class ConfigLoader
      def initialize(dir, notation:, settings_catalog:, shortcut_catalog: Mapping::ShortcutCatalog.default)
        @dir = dir
        @notation = notation
        @settings_catalog = settings_catalog
        @shortcut_catalog = shortcut_catalog
        @problems = Problems.new
      end

      def load
        raise ConfigError.new('設定ディレクトリがありません', path: @dir) unless File.directory?(@dir)

        metadata = load_single(ConfigFiles::METADATA) { |data, ctx| Schema::MetadataFile.read(data, ctx) }
        position_map = load_single(ConfigFiles::POSITION_MAP) { |data, ctx| Schema::PositionMapFile.read(data, ctx) }
        macro_files = read_files(:macros)
        tap_dance_files = read_files(:tap_dances)
        shortcuts = load_shortcuts(Schema::KeycodeField.new(@notation, build_references(macro_files, tap_dance_files)))
        keycodes = Schema::KeycodeField.new(@notation, build_references(macro_files, tap_dance_files, shortcuts))
        macros = load_macros(macro_files)
        tap_dances = load_items(tap_dance_files, keycodes) { |d, c, k| Schema::TapDanceFile.read(d, c, k) }
        settings = load_settings
        layers = position_map ? load_layers(keycodes, position_map) : []
        combos = load_items(read_files(:combos), keycodes) { |d, c, k| Schema::ComboFile.read(d, c, k) }
        @problems.raise_if_any!

        build_profile(metadata: metadata, settings: settings, position_map: position_map, layers: layers,
                      macros: macros, tap_dances: tap_dances, combos: combos, shortcuts: shortcuts)
      end

      private

      def build_profile(**parts)
        Domain::Profile.new(**parts)
      rescue InvalidValue => e
        raise InvalidConfig, [Problem.new(file: nil, message: e.message)]
      end

      # ---- 1 つだけのファイル ----

      # base（拡張子なし）を読んで yield する。読めないときは nil。
      # ファイルがなければ、missing を渡していればそれを返し、渡していなければ問題を記録して nil
      def load_single(base, **missing)
        rel = single_file(base)
        unless rel
          return missing[:missing] if missing.key?(:missing)

          return @problems.add(ConfigFiles.single_path(base), nil, 'ファイルがありません')
        end

        data = read_yaml(rel)
        data == :unreadable ? nil : yield(data, context(rel))
      end

      def single_file(base)
        found = ConfigFiles::EXTENSIONS.map { |ext| "#{base}#{ext}" }.select { |rel| File.file?(path(rel)) }
        if found.size > 1
          @problems.add(found.last, nil, "#{found.first} と同じ名前のファイルがあります。どちらか 1 つにしてください")
        end
        found.first
      end

      # shortcuts.yaml の値は Macro('名前') / TapDance('名前') を使えるが、Shortcut('名前') は使えない
      def load_shortcuts(keycodes)
        load_single(ConfigFiles::SHORTCUTS, missing: Domain::ShortcutLibrary::EMPTY) do |data, ctx|
          Schema::ShortcutsFile.read(data, ctx, keycodes)
        end || Domain::ShortcutLibrary::EMPTY
      end

      def load_settings
        load_single(ConfigFiles::SETTINGS, missing: Domain::QmkSettings::EMPTY) do |data, ctx|
          Schema::SettingsFile.read(data, ctx, @settings_catalog)
        end
      end

      # ---- 番号の付いたファイル ----

      # [[相対パス, 内容], ...]（読めなかったファイルは問題を記録して除く）
      def read_files(kind)
        ConfigFiles.list(@dir, kind).filter_map do |rel|
          data = read_yaml(rel)
          [rel, data] unless data == :unreadable
        end
      end

      # shortcuts を渡したときだけ同梱のショートカットも引けるようにする（shortcuts.yaml の値には Shortcut(...) を書けないため）
      def build_references(macro_files, tap_dance_files, shortcuts = nil)
        Mapping::References.new(macros: names(macro_files), tap_dances: names(tap_dance_files),
                                shortcuts: shortcuts ? shortcuts.entries : {},
                                preset_shortcuts: shortcuts ? @shortcut_catalog.library(@notation).entries : {})
      end

      # 名前 => 番号（名前が重複していれば先のもの。重複は Profile#diagnostics が報告する）
      def names(files)
        files.filter_map { |_, data| Schema::Header.call(data) }
             .each_with_object({}) { |(name, index), h| h[name] = index unless h.key?(name) }
      end

      # マクロのキーは名前参照を使わない（旧 Macro と同じ）
      def load_macros(files)
        load_items(files, Schema::KeycodeField.new(@notation)) { |d, c, k| Schema::MacroFile.read(d, c, k) }
      end

      def load_items(files, keycodes)
        files.filter_map { |rel, data| yield(data, context(rel), keycodes) }
      end

      def load_layers(keycodes, position_map)
        read_files(:layers).filter_map do |rel, data|
          ctx = context(rel)
          layer = Schema::LayerFile.read(data, ctx, keycodes, position_map)
          check_layer_number(rel, layer, ctx) if layer
          layer
        end
      end

      # ファイル名の先頭の番号（3_symbols.yaml の 3）と index が違えば問題にする
      def check_layer_number(rel, layer, ctx)
        number = ConfigFiles.leading_number(rel)
        return if number.nil? || number == layer.index

        ctx.problem('index', "ファイル名の番号（#{number}）と index（#{layer.index}）が違います")
      end

      # ---- 共通 ----

      def path(rel) = File.join(@dir, rel)

      def context(rel) = Schema::Context.new(rel, @problems)

      def read_yaml(rel)
        YamlFile.read(path(rel))
      rescue YamlFile::Unreadable => e
        @problems.add(rel, nil, e.message)
        :unreadable
      end
    end
  end
end
