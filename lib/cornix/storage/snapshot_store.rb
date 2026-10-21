# frozen_string_literal: true

require 'fileutils'
require 'time'

module Cornix
  module Storage
    # キーボードの状態と compile の出力の履歴（スナップショット）の置き場（旧 BackupStore）。
    #
    # スナップショットは dir/<YYYYmmdd-HHMMSS>-<種類>/layout.vil。上書きしない（同じ秒・同じ種類なら名前に -2, -3 … を付ける）。
    # 種類（KINDS）:
    #   read        キーボードを読んだとき（pull / status / apply / restore / device read / device diff など）
    #   build       compile の出力
    #   backup      cornix device backup（MCP の backup）で明示的に保存したとき
    #   pre-apply   apply で書き込む直前の状態
    #   pre-restore restore で書き込む直前の状態
    # read と build は種類ごとに新しいほうから KEEP 件だけ残し、古いものは保存のたびに消す（ほかは消さない）。
    #
    # 前の版の置き場 legacy_dir（tmp/device_backups/<YYYYmmdd-HHMMSS>.vil）は読むほうだけ残し、種類 legacy として一覧に入れる
    class SnapshotStore
      KINDS = %w[read build backup pre-apply pre-restore].freeze
      LEGACY = 'legacy'
      # 古いものを消す種類と、残す件数
      PRUNED_KINDS = %w[read build].freeze
      KEEP = 50
      FILE_NAME = 'layout.vil'
      TIME_FORMAT = '%Y%m%d-%H%M%S'
      NAME = /\A(?<time>\d{8}-\d{6})-(?<kind>#{Regexp.union(KINDS).source})(?:-(?<seq>\d+))?\z/
      LEGACY_NAME = /\A(?<time>\d{8}-\d{6})\.vil\z/

      # 1 件のスナップショット。path は layout.vil のパス、dir はスナップショットのディレクトリ（legacy は nil）
      class Snapshot < Data.define(:name, :kind, :time, :path, :dir)
        def legacy? = kind == LEGACY
        def to_h = { 'name' => name, 'kind' => kind, 'time' => time.iso8601, 'path' => path }
      end

      def initialize(dir, legacy_dir: nil, vil_file: VilFile.new)
        @dir = dir
        @legacy_dir = legacy_dir
        @vil_file = vil_file
      end

      attr_reader :dir, :legacy_dir

      # イメージを新しいスナップショットとして保存し、layout.vil のパスを返す
      def save(image, kind:, time: Time.now)
        check_kind!(kind)
        FileUtils.mkdir_p(@dir)
        target = new_dir(kind, time)
        path = @vil_file.write(image, File.join(target, FILE_NAME))
        prune(kind)
        path
      end

      # スナップショットを新しい順に返す（kind で絞り込める。legacy も指定できる）
      def list(kind: nil)
        check_kind!(kind, legacy: true) if kind
        all = snapshots + legacy_snapshots
        all = all.select { |snapshot| snapshot.kind == kind } if kind
        all.sort_by { |snapshot| sort_key(snapshot) }.reverse
      end

      # 種類（省略時はすべて）の最新のスナップショット（なければ nil）
      def latest(kind: nil) = list(kind: kind).first

      # 戻す元の layout.vil のパスを決める。見つからなければ ConfigError。
      # - nil: 最新の pre-apply（なければ前の版のバックアップ legacy の最新）= 直前の apply の前の状態
      # - スナップショットの名前・ディレクトリ・layout.vil のパス、legacy のファイル名（拡張子は省略可）、任意の .vil のパス
      def resolve(path_or_name = nil)
        return default_source if path_or_name.nil? || path_or_name.to_s.empty?

        name = path_or_name.to_s
        found = candidates(name).find { |path| File.file?(path) }
        raise ConfigError.new('スナップショットが見つかりません', path: name) unless found

        File.expand_path(found)
      end

      # スナップショットを読んで Image::DeviceImage を返す（引数は resolve と同じ）
      def load(path_or_name = nil)
        @vil_file.read(resolve(path_or_name))
      end

      private

      def check_kind!(kind, legacy: false)
        allowed = legacy ? [*KINDS, LEGACY] : KINDS
        return if allowed.include?(kind)

        raise ArgumentError, "知らないスナップショットの種類です: #{kind}（#{allowed.join(' / ')}）"
      end

      # 同じ名前があれば -2, -3 … を付ける（mkdir の失敗で、同時に作られたときも重ならない）
      def new_dir(kind, time)
        base = "#{time.strftime(TIME_FORMAT)}-#{kind}"
        (1..).each do |seq|
          path = File.join(@dir, seq == 1 ? base : "#{base}-#{seq}")
          Dir.mkdir(path)
          return path
        rescue Errno::EEXIST
          next
        end
      end

      def prune(kind)
        return unless PRUNED_KINDS.include?(kind)

        snapshots.select { |snapshot| snapshot.kind == kind }
                 .sort_by { |snapshot| sort_key(snapshot) }.reverse
                 .drop(KEEP).each { |snapshot| FileUtils.rm_rf(snapshot.dir) }
      end

      def snapshots
        Dir.glob(File.join(@dir, '*', FILE_NAME)).filter_map do |path|
          dir = File.dirname(path)
          match = NAME.match(File.basename(dir)) or next
          Snapshot.new(name: File.basename(dir), kind: match[:kind], time: parse_time(match[:time]), path: path, dir: dir)
        end
      end

      def legacy_snapshots
        return [] unless @legacy_dir

        Dir.glob(File.join(@legacy_dir, '*.vil')).filter_map do |path|
          match = LEGACY_NAME.match(File.basename(path)) or next
          Snapshot.new(name: File.basename(path, '.vil'), kind: LEGACY, time: parse_time(match[:time]), path: path, dir: nil)
        end
      end

      # 日時の順。同じ秒なら -2, -3 … の順、それも同じなら名前の順
      def sort_key(snapshot)
        [snapshot.time, NAME.match(snapshot.name)&.[](:seq).to_i, snapshot.name]
      end

      def parse_time(text) = Time.strptime(text, TIME_FORMAT)

      def default_source
        snapshot = latest(kind: 'pre-apply') || latest(kind: LEGACY)
        return snapshot.path if snapshot

        raise ConfigError.new('戻す元のスナップショット（apply の前の状態）がありません', path: @dir)
      end

      def candidates(name)
        paths = [name, File.join(name, FILE_NAME), File.join(@dir, name, FILE_NAME)]
        paths += [File.join(@legacy_dir, name), File.join(@legacy_dir, "#{name}.vil")] if @legacy_dir
        paths
      end
    end
  end
end
