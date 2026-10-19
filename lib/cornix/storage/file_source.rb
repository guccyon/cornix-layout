# frozen_string_literal: true

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

      # base の上に、いくつかのファイルの中身を差し替えて見せる
      class Overlay
        def initialize(base, files)
          @base = base
          @files = files.to_h { |rel, text| [rel.to_s, text&.to_s] }.freeze
        end

        def dir = @base.dir

        def read(rel)
          rel = rel.to_s
          return @base.read(rel) unless @files.key?(rel)

          @files[rel] or raise Errno::ENOENT, File.join(dir, rel)
        end

        def exist?(rel) = @files.key?(rel.to_s) ? !@files[rel.to_s].nil? : @base.exist?(rel)

        def list(kind)
          added = @files.filter_map { |rel, text| rel if text && ConfigFiles.kind_file?(rel, kind) }
          (@base.list(kind) + added).uniq.select { |rel| exist?(rel) }.sort
        end

        def directory? = @base.directory?
      end
    end
  end
end
