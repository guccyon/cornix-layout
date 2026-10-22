# frozen_string_literal: true

require_relative 'use_case'

module Cornix
  module Application
    # 設定ファイルの名前と name / description を変える（旧 FileRenamer）→ RenameOutcome。
    #
    #   RenameFiles.new(env).check(plan)          # => 事前検証の問題（文字列の配列。空なら実行できる）
    #   RenameFiles.new(env).call([plan, ...])    # 全部成功するか、全部元に戻すか
    #
    # call の流れ:
    # 1. すべての計画を事前検証する（ファイルがある、行き先が空いている、YAML が読める）。
    #    番号はファイルの index: だけで決まるので、ファイル名の番号の接頭辞は変えても足しても外してもよい（issue #85）
    # 2. 変更前の設定を読み込んで compile した DeviceImage を覚える（verify: false なら省く）
    # 3. config/ を config.backup_<日時>/ に複写する
    # 4. 1 件ずつ: name / description を書き換え（その行だけ）、ファイル名を変え、マクロ・タップダンスの name が
    #    変わったら全設定ファイルの Macro('旧名') / TapDance('旧名') を新しい名前に書き換える（テキストの置き換え）
    # 5. 変更後の設定を読み込んで compile した DeviceImage が変更前と同じことを確かめる
    # どこかで失敗したらバックアップから元に戻す（バックアップ自体は残す）
    class RenameFiles < UseCase
      REFERENCE_FUNCTIONS = { 'macro' => 'Macro', 'tap_dance' => 'TapDance' }.freeze
      # ファイル名の番号の接頭辞（03_）。拡張の名前の変更（Editor::ItemEdits::Rename）が保つのに使う
      INDEX_PREFIX = /\A(\d+_)/

      # → 問題の文字列の配列
      def check(plan)
        plan = RenamePlan.from_h(plan) unless plan.is_a?(RenamePlan)
        errors = []
        errors << "Missing 'old_path' field" unless plan.old_path
        errors << "Missing 'new_basename' field" unless plan.new_basename
        return errors unless errors.empty?

        path = resolve(plan.old_path)
        return ["File not found: #{path}"] unless File.file?(path)

        new_path = File.join(File.dirname(path), plan.new_basename)
        errors << "Destination file already exists: #{new_path}" if File.exist?(new_path) && new_path != path
        begin
          editor.read(path)
        rescue Storage::YamlFile::Unreadable => e
          errors << "Invalid YAML syntax: #{e.message}"
        end
        errors
      end

      def call(plans, verify: true)
        plans = plans.map { |p| p.is_a?(RenamePlan) ? p : RenamePlan.from_h(p) }
        errors = plans.each_with_index.flat_map { |plan, i| check(plan).map { |e| "Plan #{i}: #{e}" } }
        return RenameOutcome.new(success: false, failed: plans.map(&:to_h), errors: errors) unless errors.empty?

        before = nil
        if verify
          before, error = compiled
          return RenameOutcome.new(success: false, errors: ["Configuration could not be compiled before rename: #{error}"]) if error
        end

        backup = editor.backup
        completed = []
        failed = []
        plans.each do |plan|
          result = apply(plan)
          result.success? ? completed << result : failed << { plan: plan.to_h, error: result.error }
        end
        unless failed.empty?
          return rollback(backup, completed, failed, ['Some renames failed. Rolling back...'])
        end
        return success(backup, completed, nil) unless verify

        after, error = compiled
        error ||= 'compiled layout differs from the layout before rename' unless after == before
        if error
          return rollback(backup, completed, failed, ["Compilation verification failed: #{error}", 'Rolling back...'])
        end

        success(backup, completed, true)
      end

      # config.backup_* の一覧 / 削除
      def backups = editor.backups
      def delete_backup(path) = editor.delete_backup(path)

      private

      def editor = env.config_editor

      def resolve(path) = editor.resolve(path, base: env.root)

      # → [DeviceImage, nil] または [nil, エラーメッセージ]
      def compiled
        [env.mapper.to_image(env.repository.load), nil]
      rescue Cornix::Error => e
        [nil, e.message]
      end

      def apply(plan)
        path = resolve(plan.old_path)
        old_name = plan.name && current_name(path, plan.type)
        new_path = File.join(File.dirname(path), plan.new_basename)
        editor.update_fields(path, plan.content_updates)
        new_path = editor.rename(path, plan.new_basename)
        updated = update_references(plan, old_name)
        RenamedFile.new(success: true, old_path: path, new_path: new_path, updated_references: updated)
      rescue Cornix::Error, SystemCallError, Storage::YamlFile::Unreadable => e
        RenamedFile.new(success: false, old_path: path, new_path: new_path, error: "Rename failed: #{e.message}")
      end

      # name を省いたプリセットのマクロは preset の名前（Macro('アプリ:カテゴリ:ラベル') で参照されている）
      def current_name(path, type)
        Storage::Schema::Header.name_of(editor.read(path), preset: type == 'macro')
      end

      def update_references(plan, old_name)
        function = REFERENCE_FUNCTIONS[plan.type]
        return [] unless function && old_name.is_a?(String) && plan.name && old_name != plan.name

        editor.replace_references(function, old_name, plan.name)
      end

      def success(backup, completed, verified)
        RenameOutcome.new(success: true, completed: completed, backup_path: backup, verified: verified)
      end

      def rollback(backup, completed, failed, errors)
        RenameOutcome.new(success: false, completed: completed, failed: failed, errors: errors, backup_path: backup,
                          rollback_completed: editor.restore(backup))
      end
    end
  end
end
