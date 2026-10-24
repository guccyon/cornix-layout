# frozen_string_literal: true

require_relative 'profile_not_found'

module Cornix
  module Application
    module Editor
      # device のサーバー（cornix serve --device）の中身（protocol.md の 14.3〜14.5）。実機を比べる・反映する・戻す。
      # 結果は約束の形の Hash（キーはシンボル。パスはワークスペースのフォルダ root からの相対。外なら絶対）。
      #
      #   ops = DeviceOperations.new(root: '/path/to/workspace')
      #   ops.compare('profiles/default', progress: ->(phase, done, total) { ... })   #=> { plan: {...}, source: "tmp/…/layout.vil" }
      #   ops.apply('profiles/default', token: '…')                                   #=> { applied: 3, backup: "tmp/…", remaining: [] }
      #   ops.backups('profiles/default')                                             #=> { backups: [{ name:, path:, createdAt:, kind: }] }
      #   ops.compare_backup('profiles/default', '20261021-101500-pre-apply')
      #   ops.restore('profiles/default', '20261021-101500-pre-apply', token: '…')
      #
      # dir はワークスペースのフォルダからの相対パス（profile/list の dir）か絶対パス。ディレクトリがなければ ProfileNotFound。
      # Environment は Workspace の決まり（tmp は tmp/profiles/<名前>/ など）で、env_factory が Workspace から作る
      # （テストでは device_opener に偽の実機を渡す）。キーボードへの接続はメソッドごとに開いて閉じる。
      #
      # 失敗: compile できない → CompileFailed（何も読まない）、知らないバックアップ → UnknownBackup、
      # 実機の失敗は Cornix::DeviceUnavailable / WriteIncomplete（backup は相対パスにする）/ PlanChanged / PlanRejected / PlanError をそのまま。
      # progress（省略可）は ->(phase, done, total)（phase は :read / :write / :verify）。progress が送出した例外はそのまま抜ける（取り消し）
      class DeviceOperations
        # 一覧に出すバックアップの種類（read と build は数が多く、戻す先には向かない）
        BACKUP_KINDS = %w[pre-apply pre-restore backup legacy].freeze

        # compile できない（検証のエラー）。diagnostics は protocol.md の Diagnostic の Hash
        class CompileFailed < Cornix::Error
          attr_reader :diagnostics

          def initialize(message, diagnostics:)
            @diagnostics = diagnostics
            super(message)
          end
        end

        # device/compareBackup・device/restore の backup が一覧（BACKUP_KINDS）にない
        class UnknownBackup < Cornix::Error
          attr_reader :name

          def initialize(name)
            @name = name
            super("バックアップが見つかりません: #{name}")
          end
        end

        attr_reader :root

        def initialize(root:, env_factory: Workbench::DEFAULT_ENV)
          @root = File.expand_path(root)
          @env_factory = env_factory
        end

        def compare(dir, progress: nil)
          env = env_for(dir)
          path, profile = compile!(env)
          result = DeviceDiff.new(env).call(vil_path: path, progress: progress)
          { plan: plan(env, result, profile), source: relative(path) }
        end

        def apply(dir, token:, progress: nil)
          env = env_for(dir)
          path, profile = compile!(env)
          outcome(env, profile) do
            DeviceApply.new(env).call(vil_path: path, expected_token: token, progress: progress)
          end
        end

        def backups(dir)
          env = env_for(dir)
          { backups: listed(env).map { |snapshot| backup_entry(snapshot) } }
        end

        def compare_backup(dir, name, progress: nil)
          env = env_for(dir)
          snapshot = find_backup!(env, name)
          result = DeviceDiff.new(env).call(vil_path: snapshot.path, progress: progress)
          { plan: plan(env, result, profile_or_nil(env)), source: relative(snapshot.path) }
        end

        def restore(dir, name, token:, progress: nil)
          env = env_for(dir)
          snapshot = find_backup!(env, name)
          outcome(env, profile_or_nil(env)) do
            DeviceRestore.new(env).call(snapshot.path, expected_token: token, progress: progress)
          end
        end

        # 書き込みのメソッドに渡す前に、dir と backup が正しいかだけを確かめる（拡張が書き込みを許していないときの
        # エラーの順を、知らないプロファイル・バックアップ → 書き込みの禁止にそろえるため）
        def check!(dir, backup: nil)
          env = env_for(dir)
          find_backup!(env, backup) unless backup.nil?
          nil
        end

        private

        def env_for(dir)
          full = File.expand_path(dir.to_s, @root)
          raise ProfileNotFound.new(dir: dir) if dir.to_s.empty? || !File.directory?(full)

          @env_factory.call(Workspace.resolve(cwd: @root, root: @root, config: full, env: {}))
        end

        # 保存済みのファイルを compile する → [出力の .vil, Domain::Profile]。検証のエラーがあれば CompileFailed
        def compile!(env)
          result = Compile.new(env).call
          return [result.path, result.report.profile] if result.compiled?

          diagnostics = Diagnostics.new(ProfileReading.read(env), env.capabilities).call
          errors = result.report.errors
          message = "プロファイルに検証のエラーがあるので compile できません（#{errors.size} 件）: #{errors.first}"
          raise CompileFailed.new(message, diagnostics: diagnostics)
        end

        # 名前とキーの位置の表に使うプロファイル（検証のエラーがあっても読めればよい。読めなければ nil）
        def profile_or_nil(env)
          Validate.new(env).call.profile
        rescue Cornix::Error
          nil
        end

        def plan(env, result, profile)
          keyboard = result.keyboard
          {
            token: result.token, empty: result.empty?,
            changes: DeviceChanges.new(env, profile: profile).call(result.plan.changes),
            warnings: result.warnings.dup,
            keyboard: { name: keyboard&.name.to_s, uid: keyboard&.uid.to_s }
          }
        end

        def outcome(env, profile)
          result = yield
          { applied: result.applied, backup: result.backup && relative(result.backup),
            remaining: DeviceChanges.new(env, profile: profile).call(result.remaining_changes) }
        rescue WriteIncomplete => e
          raise WriteIncomplete.new(e.message, applied: e.applied, backup: e.backup && relative(e.backup))
        end

        def listed(env) = env.snapshot_store.list.select { |snapshot| BACKUP_KINDS.include?(snapshot.kind) }

        def find_backup!(env, name)
          listed(env).find { |snapshot| snapshot.name == name } or raise UnknownBackup, name
        end

        def backup_entry(snapshot)
          { name: snapshot.name, path: relative(snapshot.path), createdAt: snapshot.time.iso8601, kind: snapshot.kind }
        end

        def relative(path) = Workbench.relative_dir(@root, path)
      end
    end
  end
end
