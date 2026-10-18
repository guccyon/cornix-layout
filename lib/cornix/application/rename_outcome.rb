# frozen_string_literal: true

module Cornix
  module Application
    # RenameFiles の結果（旧 FileRenamer#rename_batch の戻り値）。
    #   completed: 成功した RenamedFile / failed: [{ plan:, error: }]（事前検証で落ちたときは計画そのもの）
    #   backup_path: 変更前の config/ の複写 / rollback_completed: 失敗して元に戻したか（戻していなければ nil）
    #   verified: 変更の前後で compile の結果（DeviceImage）が同じだったか（検証しなかったら nil）
    class RenameOutcome < Data.define(:success, :completed, :failed, :errors, :backup_path, :rollback_completed, :verified)
      def initialize(success:, completed: [], failed: [], errors: [], backup_path: nil, rollback_completed: nil,
                     verified: nil)
        super
      end

      def success? = success

      # 名前参照を書き換えたファイル（重複なし）
      def updated_references = completed.flat_map(&:updated_references).uniq

      def to_h
        h = { success: success, completed: completed.map(&:to_h), failed: failed, backup_path: backup_path, errors: errors }
        h[:rollback_completed] = rollback_completed unless rollback_completed.nil?
        h
      end
    end
  end
end
