# frozen_string_literal: true

require_relative '../handler'
require_relative 'draft_params'

module Cornix
  module Interface
    module EditorServer
      module Handlers
        # profile/planItemEdit: 項目の追加・削除・名前の変更・位置の名前の変更・preset の展開を、ファイルの作成・削除・改名と書き換えにする
        # （protocol.md の 12.5・13.1・14.9）。
        #   params: { profileId, baseVersions?: { file => FileVersion | null }（省けば {}）, edit: ItemEdit }
        #   VersionConflict → -32060（data: { files: }）、InvalidChange → -32602（data: { field: }）、
        #   NotLocal と Unverified → -32061（data: { address:, reason: }。名前の変更・preset の展開の照合は reason "verify"）
        # params の形の誤り（op・kind の値、項目の型、row / col が整数でないなど）は読むときに -32602 にするので、版の食い違いより先に返る。
        # v0.5（15.3）: op の use / unuse / setIndex / reorder（kind はレイヤー・マクロ・タップダンス・コンボ、項目は file で指す。reorder は files）と、
        # params の changes（今の未保存の変更。Change の読み方は profile/validate と同じ DraftParams。省けば []）
        class ProfilePlanItemEdit < Handler
          include DraftParams

          ItemEdits = Application::Editor::ItemEdits
          PlanEdits = Application::Editor::PlanEdits
          ITEM_KINDS = %w[macro tapDance combo shortcut].freeze
          INDEXED_KINDS = %w[layer macro tapDance combo].freeze
          INDEX_OPS = %w[use unuse setIndex reorder].freeze
          KINDS = {
            'create' => ITEM_KINDS + ['layer'],
            'delete' => ITEM_KINDS + ['layer'],
            'rename' => ITEM_KINDS + ['layer'],
            'expandPreset' => %w[macro],
            **INDEX_OPS.to_h { |op| [op, INDEXED_KINDS] }
          }.freeze
          HANDS = %w[left right].freeze

          rpc 'profile/planItemEdit'

          def call(params, context)
            id = param(params, 'profileId', String)
            base_versions = base_versions(params)
            edit = item_edit(param(params, 'edit', Hash))
            changes = changes(params)
            ItemEdits.new(context.workbench).call(id, base_versions: base_versions, edit: edit, changes: changes)
          rescue PlanEdits::VersionConflict => e
            raise RpcError.new(ErrorCodes::VERSION_CONFLICT, e.message, { files: e.files })
          rescue PlanEdits::InvalidChange => e
            raise RpcError.new(ErrorCodes::INVALID_PARAMS, e.message, { field: e.field })
          rescue PlanEdits::NotLocal, ItemEdits::Unverified => e
            raise RpcError.new(ErrorCodes::EDIT_NOT_LOCAL, e.message, { address: e.address, reason: e.reason })
          end

          private

          def item_edit(edit)
            op = one_of(edit, 'op', KINDS.keys + ['renamePosition'])
            return position_edit(edit) if op == 'renamePosition'

            kind = one_of(edit, 'kind', KINDS.fetch(op))
            return index_edit(edit, op, kind) if INDEX_OPS.include?(op)

            name = text(edit, 'name')
            case op
            when 'create' then create_edit(edit, kind, name)
            when 'delete' then ItemEdits::Edit.new(op: op, kind: kind, name: name, file: layer_file(edit, kind))
            when 'expandPreset' then ItemEdits::Edit.new(op: op, kind: kind, name: name)
            else ItemEdits::Edit.new(op: op, kind: kind, name: name, to: text(edit, 'to'), file: layer_file(edit, kind))
            end
          end

          def create_edit(edit, kind, name)
            if kind == 'shortcut'
              return ItemEdits::Edit.new(op: 'create', kind: kind, name: name, value: text(edit, 'value'))
            end

            preset = param(edit, 'preset', String, optional: true, field: 'edit.preset')
            invalid('edit.preset', 'preset はマクロだけに書けます') if preset && kind != 'macro'
            ItemEdits::Edit.new(op: 'create', kind: kind, name: name, preset: preset, index: layer_index(edit, kind))
          end

          # create のレイヤーの番号
          def layer_index(edit, kind)
            index = param(edit, 'index', Integer, optional: true, field: 'edit.index')
            invalid('edit.index', 'index はレイヤーだけに書けます') if !index.nil? && kind != 'layer'
            index
          end

          # delete・rename で探すレイヤーのファイル（レイヤーの名前は重なってよく、番号のないレイヤーも予定しているため。issue #84・#85）
          def layer_file(edit, kind)
            invalid('edit.index', 'index は create のときだけ書けます') if edit.key?('index')
            file = param(edit, 'file', String, optional: true, field: 'edit.file')
            invalid('edit.file', 'file はレイヤーだけに書けます') if !file.nil? && kind != 'layer'
            file
          end

          # use / unuse / setIndex（項目はファイルで指す。index は setIndex だけ）と reorder（files は文字列の配列）
          def index_edit(edit, op, kind)
            return reorder_edit(edit, kind) if op == 'reorder'

            file = text(edit, 'file')
            index = op == 'setIndex' ? param(edit, 'index', Integer, field: 'edit.index') : nil
            invalid('edit.index', 'index は setIndex のときだけ書けます') if op != 'setIndex' && edit.key?('index')
            ItemEdits::Edit.new(op: op, kind: kind, file: file, index: index)
          end

          def reorder_edit(edit, kind)
            files = param(edit, 'files', Array, field: 'edit.files')
            invalid('edit.files', 'params の edit.files はファイルのパスの文字列の配列です') unless files.all?(String)
            %w[file index].each { |name| invalid("edit.#{name}", "#{name} は reorder には書けません") if edit.key?(name) }
            ItemEdits::Edit.new(op: 'reorder', kind: kind, files: files)
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
