# frozen_string_literal: true

module Cornix
  module Application
    module Editor
      class ItemEdits
        # 項目の操作 1 つ（protocol.md の 12.5 の ItemEdit）。使わない項目は nil。
        #
        #   Edit.new(op: 'create', kind: 'macro', name: 'Copy', preset: nil)
        #   Edit.new(op: 'create', kind: 'shortcut', name: '前のタブへ', value: 'Command + Shift + [')
        #   Edit.new(op: 'create', kind: 'layer', name: 'Symbols', index: 3)   # index を省けば空いているいちばん小さい番号
        #   Edit.new(op: 'delete', kind: 'tapDance', name: 'Tab Escape')
        #   Edit.new(op: 'delete', kind: 'layer', name: 'Empty', file: 'layers/7_empty.yaml')   # レイヤーは file で探す（省けば name）
        #   Edit.new(op: 'rename', kind: 'layer', name: 'Layer 1', to: 'Symbols', file: 'layers/1_layer.yaml')
        #   Edit.new(op: 'renamePosition', hand: 'left', row: 0, col: 0, to: 'esc')
        #   Edit.new(op: 'expandPreset', kind: 'macro', name: 'Capture')
        #
        # op は "create" | "delete" | "rename" | "renamePosition" | "expandPreset"、kind は "macro" | "tapDance" | "combo" | "shortcut" | "layer"、
        # hand は "left" | "right"（約束の文字列のまま。形の検査は Interface が行う）
        Edit = Data.define(:op, :kind, :name, :to, :preset, :value, :hand, :row, :col, :index, :file) do
          def initialize(op:, kind: nil, name: nil, to: nil, preset: nil, value: nil, hand: nil, row: nil, col: nil, index: nil, file: nil) = super
        end
      end
    end
  end
end
