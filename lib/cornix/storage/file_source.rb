# frozen_string_literal: true

require 'pathname'
require_relative 'config_files'

module Cornix
  module Storage
    # 設定ディレクトリのファイルを読む口（ConfigLoader と DiagnosticLocator が使う）。rel は設定ディレクトリからの相対パス。
    #
    #   source = FileSource::Disk.new('profiles/default')
    #   source.read('layers/0_base.yml')    # => 中身（UTF-8 の文字列）。なければ Errno::ENOENT
    #   source.exist?('settings/qmk_settings.yaml')
    #   source.list(:layers)                # => ["layers/0_base.yml", ...]（ConfigFiles.list と同じ並び）
    #
    #   # 保存前の中身で読む（{ rel => 中身 }。nil はファイルがないものとして扱う）
    #   FileSource::Overlay.new(source, { 'layers/0_base.yml' => edited_text })
    module FileSource
      # ディスクの設定ディレクトリ（今までの読み方）
      class Disk
        attr_reader :dir

        def initialize(dir)
          @dir = dir.to_s
        end

        def read(rel) = File.read(File.join(@dir, rel), mode: 'r:UTF-8')

        def exist?(rel) = File.file?(File.join(@dir, rel))

        def list(kind) = ConfigFiles.list(@dir, kind)

        # 設定ディレクトリがあるか
        def directory? = File.directory?(@dir)
      end

      # base の上に、いくつかのファイルの中身を差し替えて見せる。
      # 相対パスは "./layers/x.yaml" と "layers/x.yaml" を同じものにそろえ、中身は UTF-8 として扱う（Disk と同じ）
      class Overlay
        def initialize(base, files)
          @base = base
          @files = files.to_h { |rel, text| [normalize(rel), text && utf8(text)] }.freeze
        end

        def dir = @base.dir

        def read(rel)
          rel = normalize(rel)
          return @base.read(rel) unless @files.key?(rel)

          @files[rel] or raise Errno::ENOENT, File.join(dir, rel)
        end

        def exist?(rel)
          rel = normalize(rel)
          @files.key?(rel) ? !@files[rel].nil? : @base.exist?(rel)
        end

        def list(kind)
          added = @files.filter_map { |rel, text| rel if text && ConfigFiles.kind_file?(rel, kind) }
          (@base.list(kind) + added).uniq.select { |rel| exist?(rel) }.sort
        end

        def directory? = @base.directory?

        private

        def normalize(rel) = Pathname.new(rel.to_s).cleanpath.to_s

        def utf8(text) = text.to_s.dup.force_encoding(Encoding::UTF_8).freeze
      end
    end
  end
end
