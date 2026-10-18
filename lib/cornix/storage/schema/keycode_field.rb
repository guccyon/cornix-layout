# frozen_string_literal: true

module Cornix
  module Storage
    module Schema
      # 設定ファイルのキーコードの値 ⇄ Domain::Keycode。
      # 解析は KeycodeNotation#parse の 1 回だけ（名前参照は references で解決する）
      class KeycodeField
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

        # nil なら既定値（KC_NO）
        def read_optional(raw, ctx, loc, default = Domain::Keycode::NO_KEY)
          raw.nil? ? default : read(raw, ctx, loc)
        end

        def write(keycode) = @notation.format(keycode, references: @references)
      end
    end
  end
end
