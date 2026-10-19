# frozen_string_literal: true

require_relative '../handler'

module Cornix
  module Interface
    module EditorServer
      module Handlers
        # profile/validate と profile/planEdits の params（profileId・baseVersions・changes）の読み方と、失敗の code。
        #   baseVersions: { file => FileVersion | null }（省けば {}）、changes: Change[]（省けば []）
        #   VersionConflict → -32060（data: { files: { file => 今の版 } }）、InvalidChange → -32602（data: { field: }）、
        #   NotLocal → -32061（data: { address:, reason: }）
        module DraftParams
          PlanEdits = Application::Editor::PlanEdits

          private

          def draft_call(params)
            yield param(params, 'profileId', String), base_versions(params), changes(params)
          rescue PlanEdits::VersionConflict => e
            raise RpcError.new(ErrorCodes::VERSION_CONFLICT, e.message, { files: e.files })
          rescue PlanEdits::InvalidChange => e
            raise RpcError.new(ErrorCodes::INVALID_PARAMS, e.message, { field: e.field })
          rescue PlanEdits::NotLocal => e
            raise RpcError.new(ErrorCodes::EDIT_NOT_LOCAL, e.message, { address: e.address, reason: e.reason })
          end

          def base_versions(params)
            versions = param(params, 'baseVersions', Hash, optional: true) || {}
            versions.each { |file, _| param(versions, file, String, optional: true, field: "baseVersions.#{file}") }
            versions
          end

          def changes(params)
            list = param(params, 'changes', Array, optional: true) || []
            list.each_with_index.map do |change, i|
              change = param(list, i, Hash, field: "changes[#{i}]")
              address = param(change, 'address', Hash, field: "changes[#{i}].address")
              file = param(address, 'file', String, field: "changes[#{i}].address.file")
              path = param(address, 'path', Array, field: "changes[#{i}].address.path")
              path.each_index { |j| param(path, j, String, Integer, field: "changes[#{i}].address.path[#{j}]") }
              value = param(change, 'value', String, Integer, TrueClass, FalseClass, field: "changes[#{i}].value")
              PlanEdits::Change.new(file: file, path: path, value: value)
            end
          end
        end

        # profile/planEdits: 未保存の変更をファイルの書き換え（範囲と文字）にする（protocol.md の 6.1）
        class ProfilePlanEdits < Handler
          include DraftParams

          rpc 'profile/planEdits'

          def call(params, context)
            draft_call(params) do |id, base_versions, changes|
              Application::Editor::PlanEdits.new(context.workbench).call(id, base_versions: base_versions, changes: changes)
            end
          end
        end
      end
    end
  end
end
