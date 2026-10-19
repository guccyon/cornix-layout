# frozen_string_literal: true

module Cornix
  module Application
    module Editor
      # ワークスペース（root）のプロファイル（設定ディレクトリ）の一覧と既定（protocol.md の profile/list）。
      #
      #   ListProfiles.new(root: '/path/to/workspace').call
      #   #=> { profiles: [{ dir: 'profiles/default', name: 'default' }, { dir: 'config', name: 'config' }], default: 'profiles/default' }
      #
      # 並べるもの（この順。同じディレクトリは 1 回だけ）:
      #   1. profiles/ の下のディレクトリ（名前の順。--profile に使えない名前は除く）
      #   2. .cornix.yml の config: が指すディレクトリ（あるとき）
      #   3. 後方互換の config/（中身があるとき）
      # default は root で何も指定せずに Workspace.resolve したときの設定ディレクトリで、一覧にあるときだけ返す（なければ nil）。
      # 環境変数 CORNIX_CONFIG は見ない（拡張を起動した環境によって既定が変わらないように。Init#resolves_here? と同じ）。
      # .cornix.yml が読めなければ、その分を除いて一覧を返し、default は nil にする
      class ListProfiles
        def initialize(root:)
          @root = File.expand_path(root)
        end

        def call
          workspace = resolve
          dirs = [*profile_dirs, *settings_dir(workspace), *legacy_config].uniq
          profiles = dirs.map { |dir| { dir: Workbench.relative_dir(@root, dir), name: File.basename(dir) } }
          default = workspace&.config_dir
          { profiles: profiles, default: dirs.include?(default) ? Workbench.relative_dir(@root, default) : nil }
        end

        private

        # root で何も指定せずに選ばれる設定（.cornix.yml が読めなければ nil）
        def resolve
          Workspace.resolve(cwd: @root, root: @root, env: {})
        rescue ConfigError
          nil
        end

        def profile_dirs
          base = File.join(@root, Workspace::PROFILES_DIR)
          return [] unless File.directory?(base)

          Dir.children(base).sort
             .select { |name| Workspace.valid_name?(name) && File.directory?(File.join(base, name)) }
             .map { |name| File.join(base, name) }
        end

        # .cornix.yml が選ぶディレクトリ（profile: なら profiles/ の下なので、すでに並んでいる）
        def settings_dir(workspace)
          return [] unless workspace&.source == :cornix_yml && File.directory?(workspace.config_dir)

          [workspace.config_dir]
        end

        def legacy_config
          dir = File.join(@root, Workspace::DEFAULT_CONFIG)
          File.directory?(dir) && !Dir.empty?(dir) ? [dir] : []
        end
      end
    end
  end
end
