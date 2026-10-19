# frozen_string_literal: true

module Cornix
  module Application
    module Editor
      class Snapshot
        # 開いているプロファイルの設定ディレクトリを 1 回読んだもの（profile/open の snapshot、keycode/candidates・keycode/inspect の参照先）。
        #
        #   reading = Reading.read(env)
        #   reading.files        #=> { "metadata.yaml" => "sha256:…", "settings/qmk_settings.yaml" => nil, ... }
        #   reading.profile      #=> Domain::Profile（構造検証で読めなければ nil）
        #   reading.problems     #=> [Storage::Problem]（構造検証の問題。読めたときは空）
        #   reading.repository   #=> 読んだ中身（texts）で読む Storage::ConfigRepository（意味検証の位置もこの中身で決める）
        #   reading.document(rel) #=> Storage::YamlDocument（YAML として読めなければ nil）
        #
        # 各ファイルのバイト列は 1 回だけ読み、版（FileVersion）と読み込みの両方に使う（読んでいる間に外で変わっても、
        # 版と中身が食い違わないように）。files に入れるのは設定ディレクトリの設定ファイル（ConfigFiles の構成）だけで、
        # settings/qmk_settings.yaml はなくても null で入れる（QMK 設定の Address が指すファイルで、保存で作ることがあるため）
        class Reading
          SINGLE_FILES = [Storage::ConfigFiles::METADATA, Storage::ConfigFiles::POSITION_MAP,
                          Storage::ConfigFiles::SETTINGS, Storage::ConfigFiles::SHORTCUTS].freeze
          SETTINGS_FILE = Storage::ConfigFiles.single_path(Storage::ConfigFiles::SETTINGS)

          attr_reader :files, :texts, :profile, :problems, :repository

          def self.read(env) = new(env)

          def initialize(env)
            @env = env
            dir = env.config_dir
            @texts = {}
            @files = {}
            config_files(dir).each do |rel|
              bytes = read_bytes(File.join(dir, rel))
              @files[rel] = Storage::FileVersion.of(bytes)
              @texts[rel] = bytes && bytes.dup.force_encoding(Encoding::UTF_8)
            end
            @files[SETTINGS_FILE] = nil unless settings_file
            @files.freeze
            @texts.freeze
            source = Storage::FileSource::Overlay.new(Storage::FileSource::Disk.new(dir), @texts)
            @repository = Storage::ConfigRepository.new(dir, notation: env.notation, settings_catalog: env.settings_catalog,
                                                             shortcut_catalog: env.shortcut_catalog, source: source)
            @documents = {}
            load_profile
          end

          def ok? = !@profile.nil?

          # QMK 設定のファイル（.yml も含めて、あるもの）。なければ settings/qmk_settings.yaml
          def settings_file
            Storage::ConfigFiles::EXTENSIONS.map { |ext| "#{Storage::ConfigFiles::SETTINGS}#{ext}" }
                                            .find { |rel| @texts[rel] }
          end

          # shortcuts.yaml（.yml）。なければ nil
          def shortcuts_file
            Storage::ConfigFiles::EXTENSIONS.map { |ext| "#{Storage::ConfigFiles::SHORTCUTS}#{ext}" }
                                            .find { |rel| @texts[rel] }
          end

          def document(rel)
            return @documents[rel] if @documents.key?(rel)

            text = @texts[rel]
            @documents[rel] = text && begin
              Storage::YamlDocument.parse(text)
            rescue Storage::YamlFile::Unreadable
              nil
            end
          end

          # YAML として読んだ中身（読めなければ nil）
          def data(rel)
            text = @texts[rel] or return nil
            Storage::YamlFile.parse(text)
          rescue Storage::YamlFile::Unreadable
            nil
          end

          private

          def config_files(dir)
            singles = SINGLE_FILES.flat_map do |base|
              Storage::ConfigFiles::EXTENSIONS.map { |ext| "#{base}#{ext}" }.select { |rel| File.file?(File.join(dir, rel)) }
            end
            singles + Storage::ConfigFiles::KINDS.keys.flat_map { |kind| Storage::ConfigFiles.list(dir, kind) }
          end

          def read_bytes(path)
            File.binread(path)
          rescue SystemCallError
            nil
          end

          def load_profile
            @profile = @repository.load
            @problems = [].freeze
          rescue Storage::InvalidConfig => e
            @profile = nil
            @problems = e.problems
          end
        end
      end
    end
  end
end
