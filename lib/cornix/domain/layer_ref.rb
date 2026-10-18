# frozen_string_literal: true

require_relative 'checks'

module Cornix
  module Domain
    # レイヤー番号。QMK のレイヤー操作キーで表せる 0〜31。
    # 実際に存在するレイヤー数（Cornix は 10）は Capabilities で検査する。
    class LayerRef < Data.define(:index)
      RANGE = (0..31)

      def initialize(index:)
        Checks.integer!(index, RANGE, 'レイヤー番号')
        super
      end

      def to_i = index
    end
  end
end
