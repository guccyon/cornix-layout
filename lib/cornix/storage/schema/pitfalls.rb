# frozen_string_literal: true

module Cornix
  module Storage
    module Schema
      # YAML の型の落とし穴（引用符なしの 1 が整数、yes / no / on / off が真偽値になる など）を
      # 書き直し方つきの説明にする
      module Pitfalls
        QUOTE = '文字列にするには引用符で囲んでください'
        BOOLEAN_WORDS = 'yes / no / on / off / true / false は YAML では真偽値になります'

        module_function

        # 期待した型でなかった値の説明
        def describe(value, expected)
          case value
          when nil then '値がありません'
          when true, false then "真偽値 #{value} として読まれました（#{BOOLEAN_WORDS}）。#{QUOTE}"
          when Integer then "整数 #{value} として読まれました。#{QUOTE}（例: \"#{value}\"）"
          when Float then "小数 #{value} として読まれました。#{QUOTE}"
          when String then string_text(value, expected)
          when Array then 'リストになっています'
          when Hash then 'マッピング（キー: 値）になっています'
          else "#{value.class} の値です"
          end
        end

        # マッピングのキーが文字列でないときの説明
        def key_message(key, label)
          case key
          when Integer then "#{label} #{key} が整数として読まれました。\"#{key}\" のように引用符で囲んでください"
          when true, false then "#{label} #{key} が真偽値として読まれました（#{BOOLEAN_WORDS}）。引用符で囲んでください"
          when nil then "空の#{label}があります"
          else "#{label}は文字列で書いてください: #{key.inspect}"
          end
        end

        def string_text(value, expected)
          text = "文字列 #{value.inspect} です"
          numeric = expected.include?('整数') || expected.include?('数値')
          numeric && value.match?(/\A\s*-?\d+\s*\z/) ? "#{text}（数値は引用符で囲まずに書いてください）" : text
        end
      end
    end
  end
end
