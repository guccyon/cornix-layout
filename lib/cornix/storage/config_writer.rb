# frozen_string_literal: true

require_relative 'yaml_file'
require_relative 'config_files'

module Cornix
  module Storage
    # Profile を設定ディレクトリに書く（ConfigRepository#save の中身。decompile の出力）。
    #
    # ファイル名は旧 YamlWriter と同じ規則（ConfigFiles.item_path）。中身の形も旧 YamlWriter と同じだが、次は直した:
    # - マクロ・タップダンスへの参照は名前で書く（Macro('名前') / TapDance('名前')。旧は M2 / TD(4)）
    # - settings/qmk_settings.yaml は名前の形で書く（旧は QSID の番号）
    # - キーコードは KeycodeNotation#format の正規形（別名があれば別名）
    # shortcuts.yaml はショートカットがあるときだけ書く。ショートカットの定義のちょうど 1 つと同じ値は Shortcut('名前') で書き、
    # shortcuts.yaml の値は既存のファイルと同じキーコードならその書き方のまま残す
    # 既存のファイルは上書きする。書かなかったファイルは消さない（旧 YamlWriter と同じ）
    class ConfigWriter
      def initialize(dir, notation:, settings_catalog:)
        @dir = dir
        @notation = notation
        @settings_catalog = settings_catalog
      end

      # → 書いたファイルの相対パスの一覧
      def save(profile)
        outputs = build_outputs(profile)
        ConfigFiles::KINDS.each_key { |kind| FileUtils.mkdir_p(File.join(@dir, ConfigFiles.directory(kind))) }
        outputs.each { |rel, content| YamlFile.write(File.join(@dir, rel), content) }
        outputs.keys
      end

      private

      def build_outputs(profile)
        keycodes = Schema::KeycodeField.new(@notation, Mapping::References.new(**profile.references))
        out = {
          ConfigFiles.single_path(ConfigFiles::METADATA) => dump(Schema::MetadataFile.write(profile.metadata)),
          ConfigFiles.single_path(ConfigFiles::POSITION_MAP) =>
            YamlFile.dump(Schema::PositionMapFile.write(profile.position_map), flow: true),
          ConfigFiles.single_path(ConfigFiles::SETTINGS) =>
            dump(Schema::SettingsFile.write(profile.settings, @settings_catalog))
        }
        items(out, :layers, profile.layers) { |layer| Schema::LayerFile.write(layer, keycodes, profile.position_map) }
        macro_keycodes = Schema::KeycodeField.new(@notation)
        items(out, :macros, profile.macros) { |macro| Schema::MacroFile.write(macro, macro_keycodes) }
        items(out, :tap_dances, profile.tap_dances) { |td| Schema::TapDanceFile.write(td, keycodes) }
        items(out, :combos, profile.combos) { |combo| Schema::ComboFile.write(combo, keycodes) }
        shortcuts(out, profile)
        out
      end

      def shortcuts(out, profile)
        return if profile.shortcuts.empty?

        # 定義の値に Shortcut('名前') は書けないので、ショートカットを除いた対応表で書く
        keycodes = Schema::KeycodeField.new(@notation, Mapping::References.new(**profile.references.merge(shortcuts: {})))
        # 既存のファイル（shortcuts.yml でも）があればそこに書く
        rel = ConfigFiles.single_file(@dir, ConfigFiles::SHORTCUTS)
        out[rel || ConfigFiles.single_path(ConfigFiles::SHORTCUTS)] =
          dump(Schema::ShortcutsFile.write(profile.shortcuts, keycodes, rel && existing(rel)))
      end

      # 既存のファイルの内容。読めなければ nil
      def existing(rel)
        YamlFile.read(File.join(@dir, rel))
      rescue YamlFile::Unreadable
        nil
      end

      def items(out, kind, list)
        list.each do |item|
          rel = unique(out, ConfigFiles.item_path(kind, item.index, item.name))
          out[rel] = dump(yield(item))
        end
      end

      # 番号と名前が同じ要素が複数あるときは 2 つめ以降に _2, _3 ... を付ける
      def unique(out, rel)
        return rel unless out.key?(rel)

        ext = File.extname(rel)
        base = rel.delete_suffix(ext)
        (2..).lazy.map { |n| "#{base}_#{n}#{ext}" }.find { |candidate| !out.key?(candidate) }
      end

      def dump(data) = YamlFile.dump(data)
    end
  end
end
