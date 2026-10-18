# frozen_string_literal: true

require 'digest'

module Cornix
  module Application
    # どの設定ディレクトリを使い、tmp/（ビルドの出力・デバイスのバックアップなど）をどこに置くかを決める。
    #
    # 設定ディレクトリの決まり方（上ほど優先）:
    #   1. --config DIR                    （source: :option）
    #   2. 環境変数 CORNIX_CONFIG           （source: :env）
    #   3. --profile NAME → profiles/NAME   （source: :profile_option）
    #   4. カレントから親へたどって最初に見つかる .cornix.yml（source: :cornix_yml。書き方は Storage::SettingsFile）
    #   5. どれもなければ <root>/config     （source: :default。今までどおりの置き場所）
    #
    # root（tmp/ と profiles/ を置く場所）: --root > .cornix.yml のディレクトリ > default_root（既定は Cornix::ROOT。
    # 今までどおりカレントディレクトリによらない）。
    # tmp/ は設定ディレクトリが <root>/config なら <root>/tmp のまま。それ以外は <root>/tmp/profiles/<tmp_name>/ に分ける
    class Workspace < Data.define(:root, :config_dir, :profile_name, :source, :settings_file)
      SETTINGS_FILE = Storage::SettingsFile::NAME
      PROFILES_DIR = 'profiles'
      DEFAULT_CONFIG = 'config'
      ENV_CONFIG = 'CORNIX_CONFIG'
      NAME_PATTERN = /\A[A-Za-z0-9][A-Za-z0-9._-]*\z/

      SOURCE_LABELS = {
        option: '--config', env: "環境変数 #{ENV_CONFIG}", profile_option: '--profile',
        cornix_yml: SETTINGS_FILE, default: '既定'
      }.freeze

      def self.resolve(cwd: Dir.pwd, root: nil, config: nil, profile: nil, env: ENV, default_root: Cornix::ROOT)
        Resolver.new(cwd: File.expand_path(cwd), root: root && File.expand_path(root), env: env,
                     default_root: File.expand_path(default_root)).call(config: config, profile: profile)
      end

      # profiles/NAME の形の名前として正しいか
      def self.valid_name?(name) = NAME_PATTERN.match?(name.to_s)

      def self.check_name!(name)
        return name if valid_name?(name)

        raise ConfigError, "プロファイル名に使えるのは英数字と . _ - だけです（先頭は英数字）: #{name.inspect}"
      end

      # 設定ディレクトリが <root>/config（今までどおりの置き場所。どう指定されたかによらない）
      def default? = config_dir == File.join(root, DEFAULT_CONFIG)

      # 設定ディレクトリが <root>/profiles/<profile_name>
      def profile? = config_dir == File.join(root, PROFILES_DIR, profile_name)

      def tmp_dir
        base = File.join(root, 'tmp')
        default? ? base : File.join(base, PROFILES_DIR, tmp_name)
      end

      # 表示用: 「profiles/alice（.cornix.yml）」
      def description = "#{display_path(config_dir)}（#{SOURCE_LABELS.fetch(source)}）"

      private

      # profiles/NAME なら NAME。ほかの場所は、同じ名前の別のディレクトリと混ざらないようにパスのハッシュを付ける
      def tmp_name = profile? ? profile_name : "#{profile_name}-#{Digest::SHA256.hexdigest(config_dir)[0, 8]}"

      def display_path(path)
        prefix = "#{root}/"
        path.start_with?(prefix) ? path.delete_prefix(prefix) : path
      end

      # Workspace.resolve の中身
      class Resolver
        def initialize(cwd:, root:, env:, default_root:)
          @cwd = cwd
          @root_option = root
          @env = env
          @default_root = default_root
        end

        def call(config:, profile:)
          return from_dir(config, :option) if present?(config)
          return from_dir(@env[ENV_CONFIG], :env) if present?(@env[ENV_CONFIG])
          return from_profile(profile, :profile_option, root) if present?(profile)
          return from_settings_file if settings_file

          build(File.join(root, DEFAULT_CONFIG), DEFAULT_CONFIG, :default)
        end

        private

        def present?(value) = !value.to_s.empty?

        def from_dir(dir, source, base = @cwd)
          path = File.expand_path(dir, base)
          build(path, File.basename(path), source)
        end

        def from_profile(name, source, base)
          Workspace.check_name!(name)
          build(File.join(base, PROFILES_DIR, name), name, source)
        end

        def from_settings_file
          key, value = Storage::SettingsFile.read(settings_file)
          base = File.dirname(settings_file)
          key == 'profile' ? from_profile(value, :cornix_yml, base) : from_dir(value, :cornix_yml, base)
        end

        def build(config_dir, name, source)
          Workspace.new(root: root, config_dir: config_dir, profile_name: name, source: source,
                        settings_file: settings_file)
        end

        def root = @root_option || (settings_file ? File.dirname(settings_file) : @default_root)

        # --root があればそこだけ、なければカレントから親へたどる
        def settings_file
          return @settings_file if defined?(@settings_file)

          @settings_file = @root_option ? Storage::SettingsFile.at(@root_option) : Storage::SettingsFile.find(@cwd)
        end
      end
    end
  end
end
