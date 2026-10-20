# frozen_string_literal: true

require 'yaml'
require 'fileutils'
require_relative 'yaml_file'
require_relative 'config_files'

module Cornix
  module Storage
    # 設定ディレクトリのファイルをその場で書き換える道具（rename が使う。旧 FileRenamer のファイル操作）。
    #
    #   editor = ConfigEditor.new('config')
    #   backup = editor.backup                         # config.backup_YYYYmmdd_HHMMSS/（.backup_manifest.yaml 付き）
    #   editor.update_fields('config/macros/00_macro.yaml', 'name' => 'Copy')   # ほかの行の書き方は保つ
    #   editor.rename('config/macros/00_macro.yaml', '00_copy.yaml')
    #   editor.replace_references('Macro', 'Macro 0', 'Copy')                   # 書き換えたファイル（相対パス）
    #   editor.restore(backup)                         # 失敗したときに元に戻す
    class ConfigEditor
      MANIFEST = '.backup_manifest.yaml'
      BACKUP_INFIX = '.backup_'
      TIMESTAMP = '%Y%m%d_%H%M%S'
      # 名前参照の関数（Macro('名前') / TapDance('名前')）
      REFERENCE_FUNCTIONS = %w[Macro TapDance].freeze
      # テキストの中の参照を扱える関数（replace_references_in / reference_pattern。Shortcut('名前') も）
      TEXT_REFERENCE_FUNCTIONS = %w[Macro TapDance Shortcut].freeze
      # 名前を囲む引用符（YAML の中で引用符を重ねた '' と \" も）。長いものから試す
      QUOTES = ["''", '\\"', "'", '"'].freeze

      def initialize(dir)
        @dir = File.expand_path(dir.to_s)
      end

      attr_reader :dir

      # 設定ディレクトリ全体を dir.backup_<日時> に複写してパスを返す（同じ名前があれば _2, _3 ... を付ける）
      def backup(time: Time.now)
        base = "#{@dir}#{BACKUP_INFIX}#{time.strftime(TIMESTAMP)}"
        path = base
        n = 1
        path = "#{base}_#{n += 1}" while File.exist?(path)
        FileUtils.cp_r(@dir, path)
        manifest = { 'timestamp' => time.strftime(TIMESTAMP), 'source_dir' => @dir, 'backup_dir' => path,
                     'files_count' => Dir.glob("#{path}/**/*", File::FNM_DOTMATCH).count { |f| File.file?(f) } }
        File.write(File.join(path, MANIFEST), YAML.dump(manifest))
        path
      end

      # バックアップの内容で設定ディレクトリを置き換える。成功したら true
      def restore(backup_path)
        return false unless backup_path && File.directory?(backup_path)

        FileUtils.rm_rf(@dir)
        FileUtils.mkdir_p(@dir)
        Dir.children(backup_path).each { |item| FileUtils.cp_r(File.join(backup_path, item), @dir) }
        FileUtils.rm_f(File.join(@dir, MANIFEST))
        true
      end

      # この設定ディレクトリのバックアップ（名前順）
      def backups = Dir.glob("#{@dir}#{BACKUP_INFIX}*").select { |p| File.directory?(p) }.sort

      def delete_backup(path) = FileUtils.rm_rf(path)

      # 相対パス（config/ 付きでも、設定ディレクトリからでもよい）または絶対パス → 絶対パス
      def resolve(path, base: Dir.pwd)
        return path.to_s if File.absolute_path?(path.to_s)

        expanded = File.expand_path(path.to_s, base)
        inside?(expanded) ? expanded : File.join(@dir, path.to_s)
      end

      def relative(path) = path.to_s.delete_prefix("#{@dir}/")

      def inside?(path) = path.to_s.start_with?("#{@dir}/")

      # YAML の内容（読めなければ YamlFile::Unreadable）
      def read(path) = YamlFile.read(path)

      # トップレベルの項目を書き換える。1 行で書かれた項目はその行だけを置き換え（ほかの行の書き方とコメントは保つ）、
      # それ以外（項目がない、複数行の値）はファイル全体を書き直す
      def update_fields(path, updates)
        return if updates.empty?

        data = read(path)
        raise ConfigError.new("マッピングではありません（#{data.class}）", path: relative(path)) unless data.is_a?(Hash)

        text = File.read(path, encoding: 'UTF-8')
        edited = updates.reduce(text) { |current, (key, value)| current && replace_line(current, key.to_s, value) }
        if edited && parse_or_nil(edited).then { |d| d.is_a?(Hash) && updates.all? { |k, v| d[k.to_s] == v } }
          File.write(path, edited)
        else
          File.write(path, YamlFile.dump(data.merge(updates.transform_keys(&:to_s))))
        end
      end

      # 同じディレクトリの中でファイル名を変えて新しいパスを返す
      def rename(path, new_basename)
        new_path = File.join(File.dirname(path), new_basename)
        File.rename(path, new_path) unless new_path == path
        new_path
      end

      # すべての設定ファイルの function('old_name') / function("old_name") を new_name に書き換える
      # （テキストの置き換えなので、ほかの書き方は保つ）。書き換えたファイルの相対パスを返す
      def replace_references(function, old_name, new_name)
        raise ArgumentError, "知らない参照です: #{function}" unless REFERENCE_FUNCTIONS.include?(function)
        return [] if old_name == new_name

        yaml_files.filter_map do |file|
          text = File.read(file, encoding: 'UTF-8')
          edited = self.class.replace_references_in(text, function, old_name, new_name)
          next if edited == text

          File.write(file, edited)
          relative(file)
        end
      end

      # テキストの中の function('old_name') / function("old_name") を new_name にしたテキスト（ファイルは書かない。
      # replace_references とエディタのサーバーの名前の変更が使う）。function は TEXT_REFERENCE_FUNCTIONS のどれか
      def self.replace_references_in(text, function, old_name, new_name)
        return text if old_name == new_name

        text.gsub(reference_pattern(function, old_name)) { "#{function}(#{quoted(new_name, Regexp.last_match(1))})" }
      end

      # function('name') の参照に合う正規表現（1 番目のグループが引用符）
      def self.reference_pattern(function, name)
        raise ArgumentError, "知らない参照です: #{function}" unless TEXT_REFERENCE_FUNCTIONS.include?(function)

        /\b#{function}\(\s*(#{QUOTES.map { |q| Regexp.escape(q) }.join('|')})#{Regexp.escape(name)}\1\s*\)/
      end

      # 名前に同じ引用符が含まれていれば、もう一方の引用符で囲む
      def self.quoted(name, quote)
        quote = { "'" => '"', '"' => "'" }.fetch(quote, quote) if name.include?(quote.delete('\\')[0])
        "#{quote}#{name}#{quote}"
      end
      private_class_method :quoted

      private

      def parse_or_nil(text)
        YamlFile.parse(text)
      rescue YamlFile::Unreadable
        nil
      end

      def yaml_files = Dir.glob(File.join(@dir, '**', '*.{yaml,yml}')).select { |f| File.file?(f) }.sort

      # "key: 値" の 1 行（次の行が字下げされていない）を置き換える。置き換えられなければ nil
      def replace_line(text, key, value)
        lines = text.lines
        i = lines.index { |line| line.match?(/\A#{Regexp.escape(key)}:(?:[ \t]|$)/) } or return nil
        rest = lines[i].sub(/\A#{Regexp.escape(key)}:/, '').strip
        return nil if rest.start_with?('|', '>') || rest.empty?
        return nil if lines[i + 1]&.match?(/\A[ \t]+\S/)

        replacement = YamlFile.dump({ key => value }).delete_prefix("---\n")
        (lines[0...i] + [replacement] + lines[(i + 1)..]).join
      end
    end
  end
end
