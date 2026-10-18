# frozen_string_literal: true

require_relative 'checks'

module Cornix
  module Domain
    # 修飾キーの組（左右のどちらか一方と、ctrl / shift / alt / gui の組み合わせ）。
    # QMK の 5bit 表現（bit0 ctrl, bit1 shift, bit2 alt, bit3 gui, bit4 右側）と 1 対 1 に対応する。
    # mods は生成時に正規の順（ctrl, shift, alt, gui）に並べ直すので、書き方の順序に依存しない。
    class ModifierSet < Data.define(:side, :mods)
      ORDER = %i[ctrl shift alt gui].freeze
      BITS = { ctrl: 0x01, shift: 0x02, alt: 0x04, gui: 0x08 }.freeze
      RIGHT_BIT = 0x10
      SIDES = %i[left right].freeze

      def self.from_bits(bits)
        Checks.integer!(bits, 0x01..0x1F, '修飾キーのビット')
        mods = ORDER.select { |m| bits.anybits?(BITS[m]) }
        new(side: bits.anybits?(RIGHT_BIT) ? :right : :left, mods: mods)
      end

      def initialize(side:, mods:)
        Checks.one_of!(side, SIDES, '修飾キーの左右')
        Checks.list!(mods, '修飾キー') { |m, _| Checks.one_of!(m, ORDER, '修飾キー') }
        raise InvalidValue, '修飾キーが空です' if mods.empty?
        raise InvalidValue, "修飾キーが重複しています: #{mods.inspect}" if mods.uniq.size != mods.size

        super(side: side, mods: ORDER.select { |m| mods.include?(m) }.freeze)
      end

      def bits
        mods.sum { |m| BITS[m] } | (side == :right ? RIGHT_BIT : 0)
      end

      def right? = side == :right

      def include?(mod) = mods.include?(mod)

      # 同じ側どうしの和。左右が違えば InvalidValue（QMK では表せない）
      def merge(other)
        raise InvalidValue, '左右の修飾キーは混在できません' unless other.side == side

        self.class.new(side: side, mods: (mods + other.mods).uniq)
      end
    end
  end
end
