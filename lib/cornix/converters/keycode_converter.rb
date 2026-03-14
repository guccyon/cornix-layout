# frozen_string_literal: true

require 'yaml'

module Cornix
  module Converters
    # キーコードエイリアスの解決を担当
    class KeycodeConverter
      def initialize(yaml_path)
        @data = YAML.load_file(yaml_path)
        @aliases = @data['aliases'] || {}
        @char_keycodes = @data['char_keycodes'] || {}
      end

      def resolve(keycode)
        # nil は「キーなし」を表す有効な値としてそのまま返す
        return nil if keycode.nil?

        # エイリアスを実際のQMKキーコードに変換
        # エイリアスが見つかった場合はQMKコードを返す
        return @aliases[keycode] if @aliases.key?(keycode)

        # QMK形式のキーコードはそのまま返す
        # - KC_*, QK_* で始まる: 標準QMKキーコード
        # - 大文字と数字とアンダースコア、2文字以上: QMK拡張キーコード（USER00, RGB_TOG等）
        keycode_str = keycode.to_s
        if keycode_str.match?(/^(?:KC_|QK_)[A-Z0-9_]+$/) || keycode_str.match?(/^[A-Z][A-Z0-9_]+$/)
          return keycode
        end

        # 数値や特殊な値も許可
        return keycode if keycode.is_a?(Integer) || keycode_str.match?(/^-?\d+$/)

        # 関数形式（MO(1), LT(2, KC_A)など）
        return keycode if keycode_str.match?(/^[A-Z_]+\(/)

        # それ以外は不正なキーコードとして nil を返す
        nil
      end

      # text展開用: 入力文字→QMKキーコードに変換 (char_keycodes セクションを使用)
      def resolve_char(char)
        @char_keycodes[char]
      end

      def reverse_resolve(qmk_keycode)
        # QMKキーコードからエイリアスを検索（定義順で最初にマッチ）
        @aliases.each do |alias_name, qmk_code|
          return alias_name if qmk_code == qmk_keycode
        end
        qmk_keycode  # 見つからない場合は元のキーコードを返す
      end
    end
  end
end
