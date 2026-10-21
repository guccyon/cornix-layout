# frozen_string_literal: true

module Cornix
  module Application
    # 結果の Data を JSON にできる Hash にする共通の部品（CLI の --json と MCP の結果が使う）。
    # 各結果の #to_h がこれを組み合わせる。キーは文字列、値は JSON にできるものだけにする
    module Serialize
      module_function

      # Domain::Diagnostic → { 'severity' => 'error' | 'warning', 'path', 'message' }
      def diagnostic(diag) = { 'severity' => diag.severity.to_s, 'path' => diag.path, 'message' => diag.message }

      def diagnostics(list) = list.map { |d| diagnostic(d) }

      # Planning::Change の一覧と、その説明（"場所: 現在 → 目標"）→ [{ 'description', 'kind', 場所の項目, 'from', 'to' }]
      def changes(changes, descriptions)
        changes.zip(descriptions).map { |change, description| { 'description' => description }.merge(change.to_h) }
      end

      # Workspace → { 'config_dir', 'profile', 'source', 'root' }。nil は nil
      def workspace(workspace)
        return nil if workspace.nil?

        { 'config_dir' => workspace.config_dir, 'profile' => workspace.profile_name,
          'source' => workspace.source.to_s, 'root' => workspace.root }
      end

      # 失敗の結果（CLI の --json のエラー）
      def error(message) = { 'error' => message.to_s }
    end
  end
end
