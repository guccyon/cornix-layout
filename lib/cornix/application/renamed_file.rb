# frozen_string_literal: true

module Cornix
  module Application
    # RenameFiles の 1 ファイルの結果（旧 FileRenamer#rename_file の戻り値）。
    # updated_references は名前参照（Macro('名前') など）を書き換えたファイルの相対パス
    class RenamedFile < Data.define(:success, :old_path, :new_path, :error, :updated_references)
      def initialize(success:, old_path:, new_path: nil, error: nil, updated_references: []) = super

      def success? = success

      def to_h = { success: success, old_path: old_path, new_path: new_path, error: error }
    end
  end
end
