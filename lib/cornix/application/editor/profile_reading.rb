# frozen_string_literal: true

module Cornix
  module Application
    module Editor
      # 開いているプロファイルの設定ディレクトリを、ある時点で 1 回読んだもの
      # （profile/open の snapshot、keycode/candidates・keycode/inspect の参照先。H の検証も使う）。
      #
      #   reading = ProfileReading.read(env)
      #   reading.files        #=> { "metadata.yaml" => "sha256:…", "settings/qmk_settings.yaml" => nil, ... }
      #   reading.profile      #=> Domain::Profile（構造検証で読めなければ nil）
      #   reading.problems     #=> [Storage::Problem]（構造検証の問題。読めたときは空）
      #   reading.repository   #=> 読んだ中身で読む Storage::ConfigRepository（意味検証の位置もこの中身で決める）
      #   reading.document(rel) #=> Storage::YamlDocument（なければ・YAML として読めなければ nil）
      #   reading.text(rel)    #=> 読んだ中身（UTF-8 の文字列。なければ nil）
      #   reading.with_files({ 'layers/0_base.yml' => text })   #=> 保存前の中身を重ねて読み直した ProfileReading
      #
      # 設定ファイルは Storage::FileSource::Memory.capture で 1 回だけ読み、そのバイト列を版（FileVersion）と読み込みの両方に使う。
      # 一覧も読んだ時点のもので、読み込みの途中でディスクが変わっても、版と中身が食い違わない。
      # files に入れるのは設定ファイル（ConfigFiles の構成）だけで、settings/qmk_settings.yaml（.yml も）がなければ
      # settings/qmk_settings.yaml を null で入れる（QMK 設定の Address が指すファイルで、保存で作ることがあるため）
      class ProfileReading
        SETTINGS_FILE = Storage::ConfigFiles.single_path(Storage::ConfigFiles::SETTINGS)

        attr_reader :files, :profile, :problems, :repository

        def self.read(env) = new(env)

        # source は読む中身（Storage::FileSource::Memory）。省けば env の設定ディレクトリをいま読む
        def initialize(env, source: nil)
          @env = env
          @source = source || Storage::FileSource::Memory.capture(env.config_dir)
          files = @source.files.transform_values { |bytes| Storage::FileVersion.of(bytes) }
          files[SETTINGS_FILE] = nil unless settings_file
          @files = files.freeze
          @repository = Storage::ConfigRepository.new(env.config_dir, notation: env.notation,
                                                                      settings_catalog: env.settings_catalog,
                                                                      shortcut_catalog: env.shortcut_catalog, source: @source)
          @documents = {}
          load_profile
        end

        def ok? = !@profile.nil?

        # QMK 設定のファイル（.yaml か .yml の、あるほう）。なければ nil
        def settings_file = single_file(Storage::ConfigFiles::SETTINGS)

        # shortcuts.yaml（.yml）。なければ nil
        def shortcuts_file = single_file(Storage::ConfigFiles::SHORTCUTS)

        def document(rel)
          return @documents[rel] if @documents.key?(rel)

          @documents[rel] = @source.exist?(rel) ? parse_document(@source.read(rel)) : nil
        end

        # 読んだ中身（UTF-8 の文字列。なければ nil）
        def text(rel) = @source.exist?(rel) ? @source.read(rel) : nil

        # この読んだ中身に、いくつかのファイルの保存前の中身（{ rel => テキスト }）を重ねて読み直したもの
        # （profile/validate・profile/planEdits の検証用）。ディスクは読み直さない。files の版は重ねた中身のもの
        def with_files(texts)
          files = @source.files.merge(texts.to_h { |rel, text| [rel, text.to_s.b] })
          self.class.new(@env, source: Storage::FileSource::Memory.new(@source.dir, files, directory: @source.directory?))
        end

        # YAML として読んだ中身（なければ・読めなければ nil）
        def data(rel)
          return nil unless @source.exist?(rel)

          Storage::YamlFile.parse(@source.read(rel))
        rescue Storage::YamlFile::Unreadable
          nil
        end

        private

        def single_file(base)
          Storage::ConfigFiles::EXTENSIONS.map { |ext| "#{base}#{ext}" }.find { |rel| @source.exist?(rel) }
        end

        def parse_document(text)
          Storage::YamlDocument.parse(text)
        rescue Storage::YamlFile::Unreadable
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
