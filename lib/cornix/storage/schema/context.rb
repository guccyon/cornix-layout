# frozen_string_literal: true

require_relative 'pitfalls'

module Cornix
  module Storage
    module Schema
      # 1 ファイルを読むときの道具。型の検査と問題の記録を受け持つ。
      #
      # 検査に失敗したメソッドは問題を記録して nil を返す（読み込みは続け、最後にまとめて報告する）。
      # loc はファイル内の位置（"mapping.left_hand.row0.tab"）。ファイル全体なら ''
      class Context
        attr_reader :file, :problems

        def initialize(file, problems)
          @file = file
          @problems = problems
        end

        def problem(loc, message) = problems.add(file, loc, message)

        # 値オブジェクトの生成などで出た InvalidValue を位置付きの問題にする
        def build(loc)
          yield
        rescue InvalidValue => e
          problem(loc, e.message)
        end

        # マッピング。キーは文字列で、required はすべて必要、allowed 以外のキーは問題にする
        # （問題を記録したうえで読み続ける）。マッピングでない・必須のキーがないときは nil
        def mapping(value, loc, required: [], allowed: nil, key_label: 'キー')
          return type_error(value, loc, 'マッピング（キー: 値）') unless value.is_a?(Hash)

          string_keys(value, loc, key_label)
          check_unknown_keys(value, loc, allowed) if allowed
          missing = required.reject { |k| value.key?(k) }
          problem(loc, "#{missing.join(', ')} がありません") unless missing.empty?
          missing.empty? ? value : nil
        end

        def string(value, loc, what = '文字列')
          value.is_a?(String) ? value : type_error(value, loc, what)
        end

        # 空でない文字列（名前）
        def name(value, loc, what = '名前（文字列）')
          text = string(value, loc, what) or return nil
          text.strip.empty? ? problem(loc, '名前が空です') : text
        end

        # 任意の文字列。nil なら nil、文字列でなければ問題を記録して :invalid
        def optional_string(value, loc, what = '文字列')
          return nil if value.nil?

          string(value, loc, what) || :invalid
        end

        # 注記（任意の文字列）。空の文字列は nil（注記なし）。文字列でなければ問題を記録して :invalid
        def note(value, loc)
          text = optional_string(value, loc, '注記（文字列）')
          text.is_a?(String) && text.strip.empty? ? nil : text
        end

        def integer(value, loc, what = '整数')
          value.is_a?(Integer) ? value : type_error(value, loc, what)
        end

        # range に収まる整数
        def bounded(value, loc, range, what)
          number = integer(value, loc, "#{what}（#{range.begin}〜#{range.end} の整数）") or return nil
          range.cover?(number) ? number : problem(loc, "#{what}は #{range.begin}〜#{range.end} です: #{number}")
        end

        # 説明（任意の文字列）。空の文字列は nil（説明なし）にする。文字列でなければ問題を記録して :invalid
        def description(value, loc = 'description')
          text = optional_string(value, loc, '説明（文字列）')
          text == '' ? nil : text
        end

        def list(value, loc, what = 'リスト')
          value.is_a?(Array) ? value : type_error(value, loc, what)
        end

        # 期待した型でない値の問題を記録して nil を返す。YAML の型の落とし穴は書き直し方を案内する
        def type_error(value, loc, expected)
          problem(loc, "#{expected}を書いてください: #{Pitfalls.describe(value, expected)}")
        end

        def join(loc, key) = Schema.join(loc, key)

        private

        def string_keys(hash, loc, key_label)
          hash.each_key { |k| problem(loc, Pitfalls.key_message(k, key_label)) unless k.is_a?(String) }
        end

        def check_unknown_keys(hash, loc, allowed)
          hash.each_key do |key|
            next if !key.is_a?(String) || allowed.include?(key)

            problem(join(loc, key), "未知のキーです（使えるキー: #{allowed.join(', ')}）")
          end
        end
      end

      # 位置をつなぐ（"mapping" + "left_hand" → "mapping.left_hand"、"sequence" + 0 → "sequence[0]"）
      def self.join(loc, key)
        return "#{loc}[#{key}]" if key.is_a?(Integer)
        return key.to_s if loc.nil? || loc.empty?

        "#{loc}.#{key}"
      end
    end
  end
end
