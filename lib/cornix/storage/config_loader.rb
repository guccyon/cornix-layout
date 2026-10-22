# frozen_string_literal: true

require_relative 'problems'
require_relative 'yaml_file'
require_relative 'config_files'
require_relative 'file_source'
require_relative 'unused_file'

module Cornix
  module Storage
    # 設定ディレクトリを読んで Domain::Profile を作る（ConfigRepository#load / #load_all の中身）。
    #
    # 読む順: metadata → position_map → macros（preset: は同梱のショートカットの手順にする）→ tap_dance → shortcuts（ここで Macro('名前') / TapDance('名前') /
    # Shortcut('名前') の対応表 Mapping::References を作る。Shortcut('名前') は shortcuts.yaml になければ同梱の
    # ショートカット（Mapping::ShortcutCatalog）を引く）→ settings → layers → combos。
    # キーコードの文字列は KeycodeNotation#parse で 1 回だけ解析する。
    # 問題はすべて集めて最後に 1 つの InvalidConfig にする（「ファイル: キーの位置: 内容」）。
    # ファイルは source（FileSource）から読む。既定はディスクの dir で、FileSource::Overlay を渡すと保存前の中身で読む。
    #
    # 番号は各ファイルの index: だけで決める（ファイル名の先頭の番号は読まない）。
    # index: のないか値が空（null）のファイルは未使用（Schema::Header.unused?。issue #85）: Profile に入れず、
    # 構造だけを同じ読み方で検証して UnusedFile にする（その問題は compile を止めない）。名前の参照は使っているものだけを引く
    class ConfigLoader
      # 読んだ結果。unused は未使用のファイル（UnusedFile。種類の順、ファイル名の順）
      Loaded = Data.define(:profile, :unused)

      # 未使用のファイルの構造を検証するときに仮に入れる番号（どの種類でも範囲内）
      PLACEHOLDER_INDEX = 0

      def initialize(dir, notation:, settings_catalog:, shortcut_catalog:, source: FileSource::Disk.new(dir))
        @dir = dir
        @source = source
        @notation = notation
        @settings_catalog = settings_catalog
        @shortcut_catalog = shortcut_catalog
        @problems = Problems.new
      end

      def load = load_all.profile

      def load_all
        raise ConfigError.new('設定ディレクトリがありません', path: @dir) unless @source.directory?

        metadata = load_single(ConfigFiles::METADATA) { |data, ctx| Schema::MetadataFile.read(data, ctx) }
        position_map = load_single(ConfigFiles::POSITION_MAP) { |data, ctx| Schema::PositionMapFile.read(data, ctx) }
        files = ConfigFiles::KINDS.keys.to_h { |kind| [kind, read_files(kind).partition { |_, d| !Schema::Header.unused?(d) }] }
        used = files.transform_values(&:first)
        unused = files.transform_values(&:last)
        shortcuts = load_shortcuts(Schema::KeycodeField.new(@notation, build_references(used, unused)))
        keycodes = Schema::KeycodeField.new(@notation, build_references(used, unused, shortcuts))
        readers = readers(keycodes, position_map)
        macros = load_items(used[:macros], &readers[:macros])
        tap_dances = load_items(used[:tap_dances], &readers[:tap_dances])
        settings = load_settings
        layers = position_map ? load_items(used[:layers], &readers[:layers]) : []
        combos = load_items(used[:combos], &readers[:combos])
        unused_files = unused.flat_map { |kind, list| check_unused(kind, list, readers[kind]) }
        @problems.raise_if_any!(unused: unused_files)

        profile = build_profile(metadata: metadata, settings: settings, position_map: position_map, layers: layers,
                                macros: macros, tap_dances: tap_dances, combos: combos, shortcuts: shortcuts,
                                unused: unused_files)
        Loaded.new(profile: profile, unused: unused_files.freeze)
      end

      private

      def build_profile(unused:, **parts)
        Domain::Profile.new(**parts)
      rescue InvalidValue => e
        raise InvalidConfig.new([Problem.new(file: nil, message: e.message)], unused: unused)
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
        found = ConfigFiles::EXTENSIONS.map { |ext| "#{base}#{ext}" }.select { |rel| @source.exist?(rel) }
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
        @source.list(kind).filter_map do |rel|
          data = read_yaml(rel)
          [rel, data] unless data == :unreadable
        end
      end

      # shortcuts を渡したときだけ同梱のショートカットも引けるようにする（shortcuts.yaml の値には Shortcut(...) を書けないため）。
      # 名前で引けるのは使っているものだけ。未使用のものの名前は「未使用です」の案内のためだけに渡す
      def build_references(used, unused, shortcuts = nil)
        Mapping::References.new(macros: names(used[:macros], preset: true), tap_dances: names(used[:tap_dances]),
                                shortcuts: shortcuts&.entries,
                                preset_shortcuts: shortcuts ? @shortcut_catalog.library(@notation).entries : {},
                                preset_macros: @shortcut_catalog.macro_names,
                                unused_macros: unused_names(unused[:macros], preset: true),
                                unused_tap_dances: unused_names(unused[:tap_dances]))
      end

      # 名前 => 番号（名前が重複していれば先のもの。重複は Profile#diagnostics が報告する）
      def names(files, preset: false)
        files.filter_map { |_, data| Schema::Header.call(data, preset: preset) }
             .each_with_object({}) { |(name, index), h| h[name] = index unless h.key?(name) }
      end

      def unused_names(files, preset: false)
        files.filter_map { |_, data| Schema::Header.name_of(data, preset: preset) }.grep(String)
      end

      # 種類 => 1 ファイルを読む手続き（data, ctx → 値オブジェクト。問題があれば nil）。
      # マクロのキーは名前参照を使わない（旧 Macro と同じ）。preset: は同梱のショートカットの手順にする。
      # position_map が読めなければレイヤーは読まない（nil）
      def readers(keycodes, position_map)
        presets = Schema::MacroFile::Presets.new(catalog: @shortcut_catalog, notation: @notation)
        macro_keys = Schema::KeycodeField.new(@notation)
        {
          macros: ->(data, ctx) { Schema::MacroFile.read(data, ctx, macro_keys, presets) },
          tap_dances: ->(data, ctx) { Schema::TapDanceFile.read(data, ctx, keycodes) },
          layers: position_map && ->(data, ctx) { Schema::LayerFile.read(data, ctx, keycodes, position_map) },
          combos: ->(data, ctx) { Schema::ComboFile.read(data, ctx, keycodes) }
        }
      end

      def load_items(files, &reader)
        files.filter_map { |rel, data| reader.call(data, context(rel)) }
      end

      # 未使用のファイルを、仮の番号を入れて使っているものと同じ読み方で読み、問題をファイルごとに集める。
      # 読み方がなければ（position_map が読めないレイヤー）問題なしとする（position_map の問題が先に出る）
      def check_unused(kind, files, reader)
        files.map do |rel, data|
          problems = Problems.new
          reader&.call(data.merge('index' => PLACEHOLDER_INDEX), Schema::Context.new(rel, problems))
          UnusedFile.new(kind: kind, file: rel, name: Schema::Header.name_of(data, preset: kind == :macros),
                         problems: problems.to_a)
        end
      end

      # ---- 共通 ----

      def context(rel) = Schema::Context.new(rel, @problems)

      def read_yaml(rel)
        YamlFile.parse(@source.read(rel))
      rescue SystemCallError => e
        @problems.add(rel, nil, "読めません: #{e.message}")
        :unreadable
      rescue YamlFile::Unreadable => e
        @problems.add(rel, nil, e.message)
        :unreadable
      end
    end
  end
end
