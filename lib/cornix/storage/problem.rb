# frozen_string_literal: true

module Cornix
  module Storage
    # 設定ファイルの問題 1 件。file は設定ディレクトリからの相対パス（ディレクトリ全体の問題は nil）、
    # location はファイル内のキーの位置（"mapping.left_hand.row0.tab"、"sequence[1].keys[0]"）
    class Problem < Data.define(:file, :location, :message)
      SEGMENT = /\[(\d+)\]|([^.\[\]]+)/

      # 位置の文字列 → キーの道筋（"sequence[1].keys[0]" → ["sequence", 1, "keys", 0]、"" → []）。
      # 文字列から戻すので、キーに . [ ] を含むと別の道筋になる（shortcuts.yaml の利用者が付ける名前の "Ver.2" など）。
      # レイヤー・マクロなどのキーは決まった名前か position_map の記号なので起きない
      def self.path_of(location)
        location.to_s.scan(SEGMENT).map { |index, key| index ? Integer(index, 10) : key }
      end

      def initialize(file:, message:, location: nil)
        super(file: file&.to_s&.dup&.freeze, location: location.to_s.dup.freeze, message: message.to_s.dup.freeze)
      end

      # location を道筋にしたもの（Address の path の形。注記付きの形の .key はそのまま残る）
      def path = self.class.path_of(location)

      # "ファイル: キーの位置: 内容"（空の部分は省く）
      def to_s = [file, location, message].reject { |s| s.nil? || s.empty? }.join(': ')
    end
  end
end
