# frozen_string_literal: true

require_relative 'checks'

module Cornix
  module Domain
    # QMK の設定値（Vial の QMK Settings）。values は { QSID(Integer) => 値(Integer) } で、QSID の昇順に並べ直す。
    # 真偽値の設定は 0 / 1。設定の名前・幅・型（カタログ）は Mapping が持つ
    class QmkSettings < Data.define(:values)
      QSID_RANGE = (0..0xFFFF)
      VALUE_RANGE = (0..0xFFFFFFFF)

      def initialize(values: {})
        Checks.hash!(values, 'QMK の設定') do |qsid, value|
          Checks.integer!(qsid, QSID_RANGE, 'QMK の設定の QSID')
          Checks.integer!(value, VALUE_RANGE, "QMK の設定 #{qsid} の値")
        end
        super(values: values.sort.to_h.freeze)
      end

      def [](qsid) = values[qsid]
      def key?(qsid) = values.key?(qsid)
      def empty? = values.empty?
      def size = values.size
      def to_h = values

      EMPTY = new
    end
  end
end
