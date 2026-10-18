# frozen_string_literal: true

module Cornix
  module Storage
    module Schema
      # position_map.yaml（形式は Domain::PositionMap を参照）
      #
      #   left_hand:
      #     row0: [tab, Q, W, E, R, T]
      #     ...
      #     thumb_keys: [left, middle, right]
      #   right_hand: ...
      #   encoders: { left: { push: push, ccw: ccw, cw: cw }, right: ... }
      module PositionMapFile
        HANDS = %w[left_hand right_hand].freeze
        GROUPS = %w[row0 row1 row2 row3 thumb_keys].freeze

        module_function

        def read(data, ctx)
          hash = ctx.mapping(data, '', allowed: HANDS + ['encoders']) or return nil
          HANDS.each { |hand| ctx.mapping(hash[hand], hand, allowed: GROUPS) if hash.key?(hand) }
          Domain::PositionMap.from_h(hash)
        rescue InvalidValue => e
          # Domain は問題を "position_map が不正です: 問題; 問題" の 1 つにまとめるので 1 件ずつに戻す
          e.message.sub(/\Aposition_map が不正です: /, '').split('; ').each { |m| ctx.problem('', m) }
          nil
        end

        def write(position_map) = position_map.to_h
      end
    end
  end
end
