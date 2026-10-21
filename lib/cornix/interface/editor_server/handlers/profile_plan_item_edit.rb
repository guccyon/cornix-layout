# frozen_string_literal: true

require_relative '../handler'

module Cornix
  module Interface
    module EditorServer
      module Handlers
        # profile/planItemEdit: 項目の追加・削除・名前の変更・位置の名前の変更・preset の展開を、ファイルの作成・削除・改名と書き換えにする
        # （protocol.md の 12.5・13.1・14.9）。
        #   params: { profileId, baseVersions?: { file => FileVersion | null }（省けば {}）, edit: ItemEdit }
        #   VersionConflict → -32060（data: { files: }）、InvalidChange → -32602（data: { field: }）、
        #   NotLocal と Unverified → -32061（data: { address:, reason: }。名前の変更・preset の展開の照合は reason "verify"）
        # params の形の誤り（op・kind の値、項目の型、row / col が整数でないなど）は読むときに -32602 にするので、版の食い違いより先に返る
        class ProfilePlanItemEdit < Handler
          ItemEdits = Application::Editor::ItemEdits
          PlanEdits = Application::Editor::PlanEdits
          ITEM_KINDS = %w[macro tapDance combo shortcut].freeze
          KINDS = {
            'create' => ITEM_KINDS + ['layer'],
            'delete' => ITEM_KINDS + ['layer'],
            'rename' => ITEM_KINDS + ['layer'],
            'expandPreset' => %w[macro]
          }.freeze
          HANDS = %w[left right].freeze

          rpc 'profile/planItemEdit'

          def call(params, context)
            id = param(params, 'profileId', String)
            base_versions = base_versions(params)
            edit = item_edit(param(params, 'edit', Hash))
            ItemEdits.new(context.workbench).call(id, base_versions: base_versions, edit: edit)
          rescue PlanEdits::VersionConflict => e
            raise RpcError.new(ErrorCodes::VERSION_CONFLICT, e.message, { files: e.files })
          rescue PlanEdits::InvalidChange => e
            raise RpcError.new(ErrorCodes::INVALID_PARAMS, e.message, { field: e.field })
          rescue PlanEdits::NotLocal, ItemEdits::Unverified => e
            raise RpcError.new(ErrorCodes::EDIT_NOT_LOCAL, e.message, { address: e.address, reason: e.reason })
          end

          private

          def base_versions(params)
            versions = param(params, 'baseVersions', Hash, optional: true) || {}
            versions.each { |file, _| param(versions, file, String, optional: true, field: "baseVersions.#{file}") }
            versions
          end

          def item_edit(edit)
            op = one_of(edit, 'op', KINDS.keys + ['renamePosition'])
            return position_edit(edit) if op == 'renamePosition'

            kind = one_of(edit, 'kind', KINDS.fetch(op))
            name = text(edit, 'name')
            case op
            when 'create' then create_edit(edit, kind, name)
            when 'delete', 'expandPreset' then ItemEdits::Edit.new(op: op, kind: kind, name: name)
            else ItemEdits::Edit.new(op: op, kind: kind, name: name, to: text(edit, 'to'))
            end
          end

          def create_edit(edit, kind, name)
            if kind == 'shortcut'
              return ItemEdits::Edit.new(op: 'create', kind: kind, name: name, value: text(edit, 'value'))
            end

            preset = param(edit, 'preset', String, optional: true, field: 'edit.preset')
            invalid('edit.preset', 'preset はマクロだけに書けます') if preset && kind != 'macro'
            index = param(edit, 'index', Integer, optional: true, field: 'edit.index')
            invalid('edit.index', 'index はレイヤーだけに書けます') if !index.nil? && kind != 'layer'
            ItemEdits::Edit.new(op: 'create', kind: kind, name: name, preset: preset, index: index)
          end

          def position_edit(edit)
            hand = one_of(edit, 'hand', HANDS)
            row = param(edit, 'row', Integer, field: 'edit.row')
            col = param(edit, 'col', Integer, field: 'edit.col')
            ItemEdits::Edit.new(op: 'renamePosition', hand: hand, row: row, col: col, to: text(edit, 'to'))
          end

          def text(edit, name) = param(edit, name, String, field: "edit.#{name}")

          def one_of(edit, name, values)
            value = text(edit, name)
            invalid("edit.#{name}", "params の edit.#{name} は #{values.join(' / ')} のどれかです: #{value}") unless values.include?(value)
            value
          end

          def invalid(field, message) = raise(RpcError.new(ErrorCodes::INVALID_PARAMS, message, { field: field }))
        end
      end
    end
  end
end
