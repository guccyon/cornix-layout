# frozen_string_literal: true

require_relative '../handler'

module Cornix
  module Interface
    module EditorServer
      module Handlers
        # profile/validate と profile/planEdits の params（profileId・baseVersions・changes）の読み方と、失敗の code。
        #   baseVersions: { file => FileVersion | null }（省けば {}）、changes: Change[]（省けば []）
        #   Change は protocol.md の 12.3（op は省けば set。set: value、remove: なし、insert: index と value（文字列か
        #   MacroStepValue のオブジェクト）、move: from と to。field は set と remove だけで、省けば key）
        #   VersionConflict → -32060（data: { files: { file => 今の版 } }）、InvalidChange → -32602（data: { field: }）、
        #   NotLocal → -32061（data: { address:, reason: }）
        # params の形の誤り（値が小数や null、path の要素の型、baseVersions の値の型、op・field・index・from・to）は
        # 読むときに -32602 にするので、版の食い違い（-32060）より先に返る
        module DraftParams
          PlanEdits = Application::Editor::PlanEdits
          OPS = { 'set' => :set, 'remove' => :remove, 'insert' => :insert, 'move' => :move }.freeze
          FIELDS = { 'key' => :key, 'note' => :note }.freeze

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
              at = "changes[#{i}]"
              change = param(list, i, Hash, field: at)
              address = param(change, 'address', Hash, field: "#{at}.address")
              file = param(address, 'file', String, field: "#{at}.address.file")
              path = param(address, 'path', Array, field: "#{at}.address.path")
              path.each_index { |j| param(path, j, String, Integer, field: "#{at}.address.path[#{j}]") }
              op = change_op(change, at)
              PlanEdits::Change.new(file: file, path: path, op: op, field: change_field(change, op, at), **operands(change, op, at))
            end
          end

          # op（省けば set）
          def change_op(change, at)
            op = param(change, 'op', String, optional: true, field: "#{at}.op") || 'set'
            return OPS.fetch(op) if OPS.key?(op)

            raise RpcError.new(ErrorCodes::INVALID_PARAMS, "params の #{at}.op は #{OPS.keys.join(' / ')} のどれかです",
                               { field: "#{at}.op" })
          end

          # field（省けば key）。set と remove だけ
          def change_field(change, op, at)
            field = param(change, 'field', String, optional: true, field: "#{at}.field")
            return :key if field.nil?
            return FIELDS.fetch(field) if FIELDS.key?(field) && %i[set remove].include?(op)

            raise RpcError.new(ErrorCodes::INVALID_PARAMS, "params の #{at}.field の形が違います（set と remove の key / note だけ）",
                               { field: "#{at}.field" })
          end

          # op ごとの項目（set: value、insert: index と value、move: from と to。remove はない）
          def operands(change, op, at)
            case op
            when :set then { value: param(change, 'value', String, Integer, TrueClass, FalseClass, field: "#{at}.value") }
            when :insert
              { index: param(change, 'index', Integer, field: "#{at}.index"),
                value: param(change, 'value', String, Hash, field: "#{at}.value") }
            when :move
              { from: param(change, 'from', Integer, field: "#{at}.from"), to: param(change, 'to', Integer, field: "#{at}.to") }
            else {}
            end
          end
        end
      end
    end
  end
end
