# frozen_string_literal: true

module Cornix
  module Device
    # Planning::Change の場所と内容を人が読む文字列にする（旧 Device::Keyboard#describe / #format_change）。
    #
    # formatter はキーコード（Integer）→ 文字列。省略時は Vial 名（KeycodeCatalog#vial_name）、なければ 0x... 。
    # 修飾付きなども Vial の表記にしたい場合は Mapping::VialNotation#format_code などを渡す。
    class ChangeDescriber
      def initialize(catalog: Mapping::KeycodeCatalog.default, formatter: nil)
        @formatter = formatter || ->(code) { catalog.vial_name(code) || format('0x%x', code) }
      end

      def keycode(code) = @formatter.call(code)

      def describe(change)
        case change
        when Planning::Change::SetKeycode then "レイヤー#{change.layer} (#{change.row},#{change.col})"
        when Planning::Change::SetEncoder
          "レイヤー#{change.layer} エンコーダ#{change.index} #{change.clockwise ? '時計回り' : '反時計回り'}"
        when Planning::Change::SetTapDance then "タップダンス#{change.index}"
        when Planning::Change::SetCombo then "コンボ#{change.index}"
        when Planning::Change::ReplaceMacros then "マクロ #{change.indexes.map { |i| "M#{i}" }.join(', ')}"
        when Planning::Change::SetSetting then "設定 #{change.qsid}"
        else change.kind.to_s
        end
      end

      # "場所: 現在 → 目標"
      def format_change(change)
        "#{describe(change)}: #{value(change, change.from)} → #{value(change, change.to)}"
      end

      # change の値（from か to）の表記（format_change の「現在」「目標」と同じ）
      def value(change, v)
        case change
        when Planning::Change::SetKeycode, Planning::Change::SetEncoder then keycode(v)
        when Planning::Change::SetTapDance
          "[#{[v.on_tap, v.on_hold, v.on_double_tap, v.on_tap_hold].map { |k| keycode(k) }.join(', ')}, #{v.tapping_term}ms]"
        when Planning::Change::SetCombo then "[#{v.keys.map { |k| keycode(k) }.join(' + ')} → #{keycode(v.output)}]"
        when Planning::Change::ReplaceMacros then change.indexes.map { |i| macro(v[i] || []) }.join(' / ')
        else v.to_s
        end
      end

      private

      def macro(actions)
        actions.map do |a|
          a.value.nil? ? [a.kind.to_s, *a.keys.map { |k| keycode(k) }] : [a.kind.to_s, a.value]
        end.to_json
      end
    end
  end
end
