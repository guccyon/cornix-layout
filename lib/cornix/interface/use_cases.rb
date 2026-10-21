# frozen_string_literal: true

module Cornix
  module Interface
    # CLI と MCP サーバーが使うユースケースの表。各値は ->(env) { #call を持つユースケース }。
    # 既定値は呼ばれたときに初めて Application の定数を参照する。テストでは一部だけ差し替えてよい
    module UseCases
      NAMES = {
        device_info: :DeviceInfo, device_read: :DeviceRead, device_backup: :DeviceBackup,
        device_diff: :DeviceDiff, device_apply: :DeviceApply, device_restore: :DeviceRestore,
        list_snapshots: :ListSnapshots, pull: :Pull,
        compile: :Compile, decompile: :Decompile, validate: :Validate, cleanup: :Cleanup,
        rename_files: :RenameFiles, suggest_renames: :SuggestRenames, init: :Init
      }.freeze

      module_function

      def default
        NAMES.to_h { |key, const| [key, ->(env) { Application.const_get(const).new(env) }] }
      end

      # 差し替え分を既定値に重ねる。知らないキーは ArgumentError
      def build(overrides = nil)
        overrides = (overrides || {}).to_h.transform_keys(&:to_sym)
        unknown = overrides.keys - NAMES.keys
        raise ArgumentError, "知らないユースケースです: #{unknown.join(', ')}" unless unknown.empty?

        default.merge(overrides).freeze
      end
    end
  end
end
