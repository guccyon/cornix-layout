# frozen_string_literal: true

require_relative 'hand_groups'

module Cornix
  module Storage
    module Schema
      # position_map.yaml（形式は Domain::PositionMap を参照）
      #
      #   left_hand:
      #     row0: [tab, Q, W, E, R, T]
      #     ...
      #     thumb: [l_left, l_mid, l_right]     # 旧名の thumb_keys でも読める（HandGroups）
      #   right_hand: ...
      #   encoders: { left: { push: push, ccw: ccw, cw: cw }, right: ... }
      module PositionMapFile
        HANDS = %w[left_hand right_hand].freeze
        GROUPS = HandGroups::GROUPS
        KEYS = (GROUPS + HandGroups::LEGACY.keys).freeze

        module_function

        def read(data, ctx)
          hash = ctx.mapping(data, '', allowed: HANDS + ['encoders']) or return nil
          HANDS.each { |hand| ctx.mapping(hash[hand], hand, allowed: KEYS) if hash.key?(hand) }
          return nil if HANDS.map { |hand| HandGroups.conflict?(hash[hand], ctx, hand) }.any?

          Domain::PositionMap.from_h(hash.to_h { |key, value| [key, HANDS.include?(key) ? HandGroups.normalize(value) : value] })
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
