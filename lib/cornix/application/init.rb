# frozen_string_literal: true

require 'fileutils'
require 'pathname'
require_relative 'use_case'
require_relative 'workspace'

module Cornix
  module Application
    # 新しい設定ディレクトリを作る（cornix init）→ InitResult。env.workspace の場所に作る。
    #
    # - 設定ディレクトリにすでにファイルがあれば ConfigError（上書きしない）
    # - .cornix.yml がなく、作る場所がこのリポジトリの config/ でなければ、次から見つかるように
    #   .cornix.yml（profiles/NAME なら「profile: NAME」、それ以外は「config: 相対パス」）を作る。あれば変えない。
    #   中身のある <root>/config があれば、次からはそれが使われなくなることを notes で知らせる
    # - このリポジトリの外に作るときは .gitignore に tmp/ と .decompile.lock を足す（設定だけのリポジトリのため）
    # - from に .vil を渡せばそれを、pull が真ならデバイスを読んで、decompile と同じ内容の設定を書く。
    #   デバイスにつながらなければ空のディレクトリだけを作り、あとから書く方法を notes で案内する
    class Init < UseCase
      # cornix init で --profile も --config もないときに作るプロファイル
      DEFAULT_PROFILE = 'default'
      GITIGNORE = '.gitignore'
      TOOL_CONFIG = File.join(Cornix::ROOT, Workspace::DEFAULT_CONFIG)
      IGNORE_LINES = ['tmp/', '.decompile.lock'].freeze

      def call(from: nil, pull: true)
        ws = env.workspace or raise ArgumentError, 'Init には workspace のある Environment が必要です'
        check_new!(ws)
        raise ConfigError.new('ファイルがありません', path: from.to_s) if from && !File.file?(from)

        created = []
        FileUtils.mkdir_p([ws.root, ws.config_dir])
        created << "#{relative(ws, ws.config_dir)}/"
        settings_created = write_settings_file(ws, created)
        write_gitignore(ws, created) unless inside_tool?(ws)
        imported_from, decompiled, device_error = import(from, pull)
        InitResult.new(config_dir: ws.config_dir, created: created, imported_from: imported_from,
                       files: decompiled&.files || [], device_error: device_error,
                       notes: notes(ws, settings_created, imported_from))
      end

      private

      def check_new!(ws)
        return unless File.exist?(ws.config_dir)
        raise ConfigError.new('ディレクトリではありません', path: ws.config_dir) unless File.directory?(ws.config_dir)
        return if Dir.empty?(ws.config_dir)

        raise ConfigError.new('設定ディレクトリがすでにあります（上書きしません）', path: ws.config_dir)
      end

      def settings_path(ws) = File.join(ws.root, Workspace::SETTINGS_FILE)

      def write_settings_file(ws, created)
        return false if File.exist?(settings_path(ws)) || ws.config_dir == TOOL_CONFIG

        if ws.profile?
          Storage::SettingsFile.write(ws.root, 'profile', ws.profile_name)
        else
          Storage::SettingsFile.write(ws.root, 'config', relative_from(ws.root, ws.config_dir))
        end
        created << Workspace::SETTINGS_FILE
        true
      end

      def write_gitignore(ws, created)
        path = File.join(ws.root, GITIGNORE)
        text = File.exist?(path) ? File.read(path) : ''
        missing = IGNORE_LINES.reject { |line| text.lines.any? { |l| l.strip.delete_prefix('/') == line } }
        return if missing.empty?

        File.write(path, "#{text}#{"\n" unless text.empty? || text.end_with?("\n")}#{missing.join("\n")}\n")
        created << (text.empty? ? GITIGNORE : "#{GITIGNORE}（#{missing.join(', ')} を追加）")
      end

      # → [書いた元 | nil, DecompileResult | nil, つながらなかった理由 | nil]
      def import(from, pull)
        return [from, decompile(from), nil] if from
        return [nil, nil, nil] unless pull

        DeviceRead.new(env).call(output: env.decompile_input)
        [:device, decompile(env.decompile_input), nil]
      rescue DeviceError => e
        [nil, nil, e.message]
      end

      def decompile(input) = Decompile.new(env).call(input: input)

      def notes(ws, settings_created, imported_from)
        list = []
        if settings_created && legacy_config?(ws)
          list << "#{Workspace::DEFAULT_CONFIG}/ があります。#{Workspace::SETTINGS_FILE} を作ったので、次からは " \
                  "#{relative(ws, ws.config_dir)}/ が使われます（#{Workspace::DEFAULT_CONFIG}/ を使うには " \
                  "--config #{File.join(ws.root, Workspace::DEFAULT_CONFIG)} を付けるか、" \
                  "#{Workspace::SETTINGS_FILE} を消してください）"
        end
        if !settings_created && File.exist?(settings_path(ws)) && !resolves_here?(ws)
          list << "#{Workspace::SETTINGS_FILE} はすでにあるので変えていません。この設定を使うには " \
                  "#{option_for(ws)} を付けるか、#{Workspace::SETTINGS_FILE} を書き換えてください"
        end
        unless imported_from
          option = " #{option_for(ws)}" unless resolves_here?(ws)
          list << "デバイスにつないでから cornix pull#{option} を実行するか、Vial で保存した layout.vil を " \
                  "cornix decompile FILE#{option} で書き出してください"
        end
        list
      end

      # <root>/config に中身があり、それとは別の場所に作った（.cornix.yml を作ると config/ が使われなくなる）
      def legacy_config?(ws)
        legacy = File.join(ws.root, Workspace::DEFAULT_CONFIG)
        ws.config_dir != legacy && File.directory?(legacy) && !Dir.empty?(legacy)
      end

      # 何も指定せずに実行したとき（.cornix.yml や既定の置き場所で）この設定ディレクトリが使われるか
      def resolves_here?(ws)
        Workspace.resolve(cwd: ws.root, env: {}).config_dir == ws.config_dir
      rescue ConfigError
        false
      end

      def option_for(ws)
        if ws.profile?
          "--profile #{ws.profile_name}"
        else
          "--config #{ws.config_dir}"
        end
      end

      def inside_tool?(ws) = File.expand_path(ws.root) == File.expand_path(Cornix::ROOT)

      def relative(ws, path) = path.delete_prefix("#{ws.root}/")

      def relative_from(base, path) = Pathname.new(path).relative_path_from(Pathname.new(base)).to_s
    end
  end
end
