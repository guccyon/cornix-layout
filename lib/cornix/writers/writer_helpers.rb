# frozen_string_literal: true

module Cornix
  module Writers
    # YAML生成時の共通ヘルパーメソッド
    module WriterHelpers
      # YAMLクォート最適化
      # YAMLの特殊文字を正確に検出し、不要なクォートを削除
      def self.minimize_quotes(yaml_string)
        # YAMLの特殊文字パターン
        # - 行頭の -, ?, :
        # - 中間の : （キー・バリュー区切り）
        # - コメント #
        # - クォート文字 ', "
        # - その他の特殊文字（, ; @ & * ! `）
        yaml_special_pattern = /^[-?:]|:\s|[,;@&*!#`'\"]/

        # 予約語パターン（true, false, null, yes, no, on, off）
        yaml_reserved_pattern = /^(true|false|null|yes|no|on|off)$/i

        # 数値パターン（整数、浮動小数点、16進数）
        numeric_pattern = /^-?\d+(\.\d+)?$|^0x[0-9a-f]+$/i

        # エスケープシーケンスパターン
        escape_pattern = /\\/

        lines = yaml_string.split("\n")
        lines.map do |line|
          # キー部分とバリュー部分を分離
          if line =~ /^(\s*[^:]+):\s+"([^"]*)"$/
            indent_and_key = $1
            value = $2

            # クォートを保持すべきケース
            keep_quotes = (
              value.match?(yaml_special_pattern) ||
              value.match?(yaml_reserved_pattern) ||
              value.match?(numeric_pattern) ||
              value.match?(escape_pattern) ||
              value.empty?
            )

            if keep_quotes
              line  # クォート保持
            else
              "#{indent_and_key}: #{value}"  # クォート削除
            end
          else
            line  # キー・バリュー形式ではない行はそのまま
          end
        end.join("\n")
      end
    end
  end
end
