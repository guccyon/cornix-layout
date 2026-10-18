# frozen_string_literal: true

module Cornix
  module Application
    # DeviceBackup の結果（保存したバックアップのパス）
    class BackupResult < Data.define(:path)
      def to_h = { 'path' => path }
    end
  end
end
