# frozen_string_literal: true

require_relative 'profile_not_found'

module Cornix
  module Application
    module Editor
      # エディタのサーバーが開いているプロファイル（設定ディレクトリ）を持つ。1 つのワークスペース（root）に 1 つ。
      #
      #   workbench = Workbench.new(root: '/path/to/workspace')
      #   opened = workbench.open('profiles/default')   #=> OpenedProfile(id: "p1", dir: "profiles/default", name: "default", env:)
      #   workbench.fetch('p1')                         #=> 同じ OpenedProfile（なければ ProfileNotFound）
      #   workbench.versions('p1')                      #=> {}（file => FileVersion。後の作業が読み書きする「知っている版」）
      #   workbench.close('p1')
      #
      # dir はワークスペースのフォルダ（root）からの相対パスか絶対パス。結果の dir は root の中なら相対、外なら絶対にそろえる。
      # env_factory は Workspace から Environment を作る手続き（テストで差し替える）
      class Workbench
        OpenedProfile = Data.define(:id, :dir, :name, :env)

        DEFAULT_ENV = ->(workspace) { Environment.for(workspace) }

        attr_reader :root

        # path を root からの相対パス（root の外なら絶対パス）にする（profile/list と profile/open の dir の形）
        def self.relative_dir(root, path)
          base = File.expand_path(root)
          full = File.expand_path(path, base)
          return '.' if full == base

          full.start_with?("#{base}/") ? full.delete_prefix("#{base}/") : full
        end

        def initialize(root:, env_factory: DEFAULT_ENV)
          @root = File.expand_path(root)
          @env_factory = env_factory
          @opened = {}
          @versions = {}
          @next_id = 1
        end

        # 設定ディレクトリを開く。同じ dir を何度開いても、そのたびに別の id を返す（閉じるのは id ごと）
        def open(dir)
          full = File.expand_path(dir.to_s, @root)
          raise ProfileNotFound.new(dir: dir) if dir.to_s.empty? || !File.directory?(full)

          workspace = Workspace.resolve(cwd: @root, root: @root, config: full, env: {})
          id = "p#{@next_id}"
          @next_id += 1
          @versions[id] = {}
          @opened[id] = OpenedProfile.new(id: id, dir: self.class.relative_dir(@root, full),
                                          name: workspace.profile_name, env: @env_factory.call(workspace))
        end

        def fetch(id) = @opened.fetch(id) { raise ProfileNotFound.new(profile_id: id) }

        # 開いていない id でも何もしない（profile/close は通知で、応答を返せないため）
        def close(id)
          @versions.delete(id)
          @opened.delete(id)
          nil
        end

        def versions(id) = @versions.fetch(id) { raise ProfileNotFound.new(profile_id: id) }

        def opened = @opened.values
      end
    end
  end
end
