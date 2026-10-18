# frozen_string_literal: true

module Cornix
  module Storage
    module Schema
      # 設定ファイルのキーコードの値 ⇄ Domain::Keycode。
      # 解析は KeycodeNotation#parse の 1 回だけ（名前参照は references で解決する）。
      #
      # キーを割り当てる場所（レイヤーのキー、エンコーダ、タップダンスの動作、コンボの出力）には
      # 注記付きの形も書ける（read_assignment / write_assignment）:
      #   tab: Tab                        # キーコードだけ
      #   tab: { key: Tab, note: 注記 }   # 注記付き（note は省略可）
      class KeycodeField
        ASSIGNMENT_KEYS = %w[key note].freeze

        # 割り当ての読み込み結果（note は注記。なければ nil）
        Assignment = Data.define(:keycode, :note)

        # 場所 => Assignment → 場所 => 注記（注記のある場所だけ。Domain の notes: に渡す形）
        def self.notes(assignments) = assignments.filter_map { |slot, a| [slot, a.note] if a.note }.to_h

        attr_reader :references

        def initialize(notation, references = Mapping::References::NONE)
          @notation = notation
          @references = references
        end

        # 値（文字列、または 16bit の値そのものの整数）→ Keycode。解析できなければ問題を記録して nil
        def read(raw, ctx, loc)
          return ctx.type_error(raw, loc, 'キーコード（文字列）') unless raw.is_a?(String) || raw.is_a?(Integer)

          @notation.parse(raw, references: @references)
        rescue UnknownKeycode => e
          ctx.problem(loc, e.message)
        end

        def write(keycode) = @notation.format(keycode, references: @references)

        # 割り当ての値（キーコード、または { key: キーコード, note: 注記 }）→ Assignment。
        # 問題があれば記録して nil。default を渡すと値が nil のときに default（注記なし）
        def read_assignment(raw, ctx, loc, default: nil)
          return Assignment.new(keycode: default, note: nil) if raw.nil? && default
          return keycode_only(read(raw, ctx, loc)) unless raw.is_a?(Hash)

          hash = ctx.mapping(raw, loc, required: ['key'], allowed: ASSIGNMENT_KEYS) or return nil
          note = ctx.note(hash['note'], Schema.join(loc, 'note'))
          keycode = read(hash['key'], ctx, Schema.join(loc, 'key'))
          keycode && note != :invalid ? Assignment.new(keycode: keycode, note: note) : nil
        end

        # キーコードと注記 → YAML の値（注記がなければキーコードの文字列だけ）
        def write_assignment(keycode, note)
          text = write(keycode)
          note ? { 'key' => text, 'note' => note } : text
        end

        private

        def keycode_only(keycode) = keycode && Assignment.new(keycode: keycode, note: nil)
      end
    end
  end
end
