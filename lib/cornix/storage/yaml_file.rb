# frozen_string_literal: true

require 'yaml'
require 'fileutils'

module Cornix
  module Storage
    # 設定ファイル（YAML）の安全な読み書き。
    #
    # 読み込み: UTF-8 として読み（先頭の BOM は除く）、Psych.safe_load で文字列・数値・真偽値・nil・配列・
    # マッピングだけを許す。アンカー（&）とエイリアス（*）、マッピングのキーの重複はエラーにする
    # （Psych は重複したキーを黙って後の値で上書きするため）。
    #
    # 書き出し: 渡した Hash の順のまま書く（先頭に "---"、末尾に改行）。旧 YamlWriter と同じく、
    # 引用符が要らない値は引用符を外す（WriterHelpers.minimize_quotes と同じ規則。外すと別の値として
    # 読まれてしまうものは外さない）。flow: true ならスカラーだけの配列を 1 行（[a, b, c]）で書く
    module YamlFile
      # 読めなかったときの例外（message はそのまま問題の内容になる）
      class Unreadable < StandardError; end

      BOM = "﻿"
      # 旧 WriterHelpers.minimize_quotes の規則
      SPECIAL = /^[-?:|>%\[{]|:\s|[,;@&*!#`'"}\]]/
      RESERVED = /^(true|false|null|yes|no|on|off|~)$/i
      NUMERIC = /^-?\d+(\.\d+)?$|^0x[0-9a-f]+$/i
      QUOTED_LINE = /^(\s*[^:]+):\s+"([^"]*)"$/

      module_function

      # path を読んで Ruby の値を返す。空のファイルは nil
      def read(path)
        parse(File.read(path, mode: 'r:UTF-8'))
      rescue SystemCallError => e
        raise Unreadable, "読めません: #{e.message}"
      end

      # YAML の文字列を Ruby の値にする（規則は read と同じ）
      def parse(text)
        raise Unreadable, 'UTF-8 として読めません' unless text.valid_encoding?

        text = text.delete_prefix(BOM)
        check_structure!(Psych.parse(text))
        Psych.safe_load(text, aliases: false)
      rescue Psych::SyntaxError => e
        raise Unreadable, "YAML の文法エラーです（#{e.line} 行 #{e.column} 桁）: #{e.problem}"
      rescue Psych::DisallowedClass => e
        raise Unreadable, "使えない型の値があります（日付や :記号 などは引用符で囲んで文字列にしてください）: #{e.message}"
      rescue Psych::AliasesNotEnabled, Psych::BadAlias
        raise Unreadable, 'エイリアス（& と *）は使えません'
      rescue SystemCallError => e
        raise Unreadable, "読めません: #{e.message}"
      end

      # 値を YAML の文字列にする
      def dump(data, flow: false)
        tree = Psych::Visitors::YAMLTree.create(line_width: -1)
        tree << data
        stream = tree.tree
        flow_sequences!(stream) if flow
        text = stream.yaml(nil, line_width: -1)
        text = minimize_quotes(text)
        text.end_with?("\n") ? text : "#{text}\n"
      end

      # 書いて true を返す（親ディレクトリは作る）
      def write(path, content)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, content, mode: 'w:UTF-8')
        true
      end

      # --- 内部 ---

      def check_structure!(node)
        return unless node

        raise Unreadable, 'エイリアス（& と *）は使えません' if node.is_a?(Psych::Nodes::Alias)
        raise Unreadable, "アンカー（&#{node.anchor}）は使えません" if node.respond_to?(:anchor) && node.anchor

        check_duplicate_keys!(node) if node.is_a?(Psych::Nodes::Mapping)
        node.children&.each { |child| check_structure!(child) }
      end

      def check_duplicate_keys!(mapping)
        seen = {}
        mapping.children.each_slice(2) do |key, _|
          next unless key.is_a?(Psych::Nodes::Scalar)
          raise Unreadable, "キー「#{key.value}」が重複しています（#{key.start_line + 1} 行）" if seen.key?(key.value)

          seen[key.value] = true
        end
      end

      def flow_sequences!(node)
        if node.is_a?(Psych::Nodes::Sequence) && !node.children.empty? &&
           node.children.all?(Psych::Nodes::Scalar)
          node.style = Psych::Nodes::Sequence::FLOW
        end
        node.children&.each { |child| flow_sequences!(child) }
      end

      # key: "value" の行で、引用符が要らない値の引用符を外す
      def minimize_quotes(text)
        text.each_line.map do |line|
          m = QUOTED_LINE.match(line.chomp)
          next line unless m && plain_safe?(m[2])

          line.sub(/"#{Regexp.escape(m[2])}"(\s*)$/) { "#{m[2]}#{Regexp.last_match(1)}" }
        end.join
      end

      def plain_safe?(value)
        return false if value.empty? || value.match?(SPECIAL) || value.match?(RESERVED) ||
                        value.match?(NUMERIC) || value.include?('\\')

        Psych.safe_load("v: #{value}") == { 'v' => value }
      rescue Psych::Exception
        false
      end
    end
  end
end
