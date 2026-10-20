# frozen_string_literal: true

require_relative 'snapshot'

module Cornix
  module Application
    module Editor
      # 設定ディレクトリのファイルが外で変わった知らせ（protocol.md の 7.1 の workspace/didChangeFiles）を受けて、
      # 中身が知っている版と違う開いているプロファイルごとの profile/didChange の中身を作る（7.2）。
      #
      #   FileChanges.new(workbench).call(['profiles/default/layers/0_base.yml'])
      #   #=> [{ profileId: 'p1', files: { 'layers/0_base.yml' => 'sha256:…' }, snapshot: ProfileSnapshot }]
      #
      # paths はワークスペースのフォルダ（workbench.root）からの相対パスか絶対パス。開いているプロファイルのうち、
      # 設定ディレクトリそのもの・その中・その親（ディレクトリごと消えた・名前が変わった）を指すパスがあるものだけを見る。
      # 見るプロファイルは、設定ファイルの版を読んで知っている版（workbench.versions）と比べ、違うときだけ読み直す
      # （Snapshot。知っている版もそれになる）。files は知っている版と違うファイルと新しい版で、足されたファイルも入り、
      # 消えたファイルは nil。知らせのパスに入っていない設定ファイルの違いも入れる
      class FileChanges
        # before と after（{ file => FileVersion | nil }）で版の違うファイルと after の版。ないファイルは nil と同じに扱う
        def self.diff(before, after)
          (before.keys | after.keys).each_with_object({}) do |file, h|
            h[file] = after[file] unless before[file] == after[file]
          end
        end

        def initialize(workbench)
          @workbench = workbench
        end

        def call(paths)
          full = paths.map { |path| File.expand_path(path.to_s, @workbench.root) }
          @workbench.opened.filter_map do |opened|
            dir = File.expand_path(opened.env.config_dir)
            next unless full.any? { |path| related?(path, dir) }

            known = @workbench.versions(opened.id).dup
            next if self.class.diff(known, versions_on_disk(dir)).empty?

            snapshot = Snapshot.new(@workbench).call(opened.id)
            files = self.class.diff(known, snapshot[:files])
            { profileId: opened.id, files: files, snapshot: snapshot } unless files.empty?
          end
        end

        private

        # path が設定ディレクトリそのもの・その中・その親（ディレクトリごと消えた・名前が変わった）を指すか
        def related?(path, dir)
          path == dir || path.start_with?("#{dir}/") || dir.start_with?("#{path.chomp('/')}/")
        end

        # 設定ファイルの版だけを読む（読み直すかどうかの判断用。プロファイルは組み立てない）
        def versions_on_disk(dir)
          Storage::FileSource::Memory.capture(dir).files.transform_values { |bytes| Storage::FileVersion.of(bytes) }
        end
      end
    end
  end
end
