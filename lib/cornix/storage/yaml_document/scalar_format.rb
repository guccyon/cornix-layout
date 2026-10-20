# frozen_string_literal: true

require 'yaml'

module Cornix
  module Storage
    class YamlDocument
      # 書き込む値の YAML の表記（protocol.md の 6.3 の引用符の決まり）。
      #
      # - 文字列は、引用符なしで同じ文字列として読めるものは囲まない（"," "-" のように要るものだけ囲む）
      # - もとが引用符付きなら、その引用符を保つ。新しい値に同じ引用符が含まれるときはもう一方の引用符にする
      #   （ConfigEditor#quoted と同じ）
      # - 整数・真偽値（QMK 設定）はそのまま書く
      module ScalarFormat
        # 引用符なしの値の先頭に来ると意味が変わる記号
        INDICATOR = /\A[-?:,\[\]{}#&*!|>'"%@`]/
        SWAP = { "'" => '"', '"' => "'" }.freeze
        # 二重引用符の中のエスケープ（ほかの制御文字は \xHH）
        ESCAPES = { '"' => '\\"', '\\' => '\\\\', "\n" => '\\n', "\r" => '\\r', "\t" => '\\t' }.freeze

        module_function

        # value を YAML の表記にする。flow: フロー表記（{ }）の中に書くか、quote: もとの引用符（' か "。なければ nil）
        def format(value, flow: false, quote: nil)
          case value
          when String then string(value, flow: flow, quote: quote)
          when Integer, true, false then value.to_s
          else raise ArgumentError, "書けない値です: #{value.inspect}"
          end
        end

        # 並び・Hash も含めた値を 1 行の表記にする（並びと Hash はフロー表記の [a, b] と { k: v }）。
        # 並びの要素・Hash の値の中はフロー表記の中として囲む
        def inline(value, flow: false)
          case value
          when Array then "[#{value.map { |v| inline(v, flow: true) }.join(', ')}]"
          when Hash
            return '{}' if value.empty?

            "{ #{value.map { |k, v| "#{format(k.to_s, flow: true)}: #{inline(v, flow: true)}" }.join(', ')} }"
          else format(value, flow: flow)
          end
        end

        def string(value, flow:, quote:)
          if quote
            quote = SWAP.fetch(quote) if value.include?(quote)
            return quoted(value, quote)
          end
          return value if plain?(value, flow: flow)

          quoted(value, value.include?('"') || value.include?('\\') ? "'" : '"')
        end

        # 引用符なしで書いても同じ文字列として読めるか
        def plain?(value, flow: false)
          return false if value.empty? || value != value.strip || value.match?(/[\r\n\t]/) || value.match?(INDICATOR)
          return false unless reads_as?("v: #{value}\n", { 'v' => value })

          !flow || reads_as?("{v: #{value}, w: x}\n", { 'v' => value, 'w' => 'x' })
        end

        def reads_as?(yaml, expected)
          Psych.safe_load(yaml) == expected
        rescue StandardError # 文法エラー、日付などの使えない型
          false
        end

        def quoted(value, quote)
          return "'#{value.gsub("'", "''")}'" if quote == "'"

          escaped = value.gsub(/["\\\x00-\x1F\x7F]/) { |c| ESCAPES.fetch(c) { Kernel.format('\\x%02X', c.ord) } }
          "\"#{escaped}\""
        end
      end
    end
  end
end
