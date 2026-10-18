# frozen_string_literal: true

require 'fileutils'

module Cornix
  module Storage
    # キーボードのバックアップ（.vil）の置き場（旧 Device::Keyboard.backups / latest_backup / #backup）。
    #
    # ファイルは dir/<YYYYmmdd-HHMMSS>.vil。名前の順が日時の順なので、一覧は名前の降順（新しい順）。
    class BackupStore
      DEFAULT_DIR = File.join(Cornix::ROOT, 'tmp', 'device_backups')
      EXTENSION = '.vil'
      TIME_FORMAT = '%Y%m%d-%H%M%S'

      def initialize(dir = DEFAULT_DIR, vil_file: VilFile.new)
        @dir = dir
        @vil_file = vil_file
      end

      attr_reader :dir

      # イメージを日時の名前で保存してパスを返す（同じ秒に保存すると上書きする。旧実装と同じ）
      def save(image, time: Time.now)
        FileUtils.mkdir_p(@dir)
        @vil_file.write(image, File.join(@dir, "#{time.strftime(TIME_FORMAT)}#{EXTENSION}"))
      end

      # バックアップのパスを新しい順に返す
      def list
        Dir.glob(File.join(@dir, "*#{EXTENSION}")).sort.reverse
      end

      # 最新のバックアップのパス（なければ nil）
      def latest
        list.first
      end

      # パス・ファイル名（拡張子は省略可）・nil（最新）からバックアップのパスを決める。見つからなければ ConfigError
      def resolve(path_or_name = nil)
        if path_or_name.nil? || path_or_name.to_s.empty?
          return latest || raise(ConfigError.new('バックアップがありません', path: @dir))
        end

        name = path_or_name.to_s
        candidates = [name, File.join(@dir, name), File.join(@dir, "#{name}#{EXTENSION}")]
        found = candidates.find { |path| File.file?(path) }
        raise ConfigError.new('バックアップが見つかりません', path: name) unless found

        File.expand_path(found)
      end

      # バックアップを読んで Image::DeviceImage を返す（引数は resolve と同じ）
      def load(path_or_name = nil)
        @vil_file.read(resolve(path_or_name))
      end
    end
  end
end
