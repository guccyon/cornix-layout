# frozen_string_literal: true

module Cornix
  module Storage
    # 未使用の設定ファイル 1 つ（layers/ macros/ tap_dance/ combos/ の、index: のないか値が空のファイル。issue #85）。
    # compile に含めず Domain::Profile にも入れないが、構造は検証する。
    #   kind      ConfigFiles の種類（:layers / :macros / :tap_dances / :combos）
    #   file      設定ディレクトリからの相対パス
    #   name      ファイルの name（マクロは name がなければ preset の名前）。書いていなければ nil
    #   problems  構造検証の問題（Problem の一覧）。compile は止めず、validate は警告として出す
    #   item      読んだ値オブジェクト（Domain::Layer / Macro / TapDance / Combo。index は仮の 0）。問題があれば nil。
    #             エディタが未使用の項目の中身を画面に描くのに使う（protocol.md の 15.1）
    class UnusedFile < Data.define(:kind, :file, :name, :problems, :item)
      def initialize(kind:, file:, name: nil, problems: [], item: nil)
        super(kind: kind, file: file.to_s.dup.freeze, name: name.is_a?(String) ? name.dup.freeze : nil,
              problems: problems.dup.freeze, item: problems.empty? ? item : nil)
      end

      def to_h = { 'kind' => kind.to_s, 'file' => file, 'name' => name }
    end
  end
end
