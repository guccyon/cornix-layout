# frozen_string_literal: true

module Cornix
  module Domain
    class PositionMap
      # position_map.yaml の Hash を検査して groups / encoders にする。問題はまとめて InvalidValue で報告する
      class Parser
        def initialize(hash)
          @hash = hash
          @errors = []
        end

        def call
          raise InvalidValue, "position_map は Hash です: #{@hash.inspect}" unless @hash.is_a?(Hash)

          groups = HANDS.keys.to_h { |hand_key| [hand_key, parse_hand(hand_key)] }.freeze
          encoders = parse_encoders
          raise InvalidValue, "position_map が不正です: #{@errors.join('; ')}" unless @errors.empty?

          [groups, encoders]
        end

        private

        def parse_hand(hand_key)
          data = @hash[hand_key]
          return missing(hand_key) unless data.is_a?(Hash)

          GROUPS.to_h { |group_key, (_, _, count)| [group_key, parse_group("#{hand_key}.#{group_key}", data[group_key], count)] }
                .freeze
        end

        def parse_group(path, list, count)
          return missing(path, []) unless list.is_a?(Array)

          @errors << "#{path} は #{count} 個です: #{list.size} 個" unless list.size == count
          symbols = list.each_with_index.map { |sym, i| parse_symbol("#{path}[#{i}]", sym) }
          symbols.compact.tally.each { |sym, n| @errors << "#{path} でシンボル #{sym} が重複しています" if n > 1 }
          symbols.freeze
        end

        def parse_encoders
          data = @hash['encoders']
          return missing('encoders', {}) unless data.is_a?(Hash)

          ENCODER_SIDES.to_h do |side|
            actions = data[side.to_s]
            next [side, missing("encoders.#{side}", {})] unless actions.is_a?(Hash)

            [side, ENCODER_ACTIONS.to_h { |a| [a, parse_symbol("encoders.#{side}.#{a}", actions[a])] }.freeze]
          end.freeze
        end

        def parse_symbol(path, sym)
          text = sym.is_a?(Integer) ? sym.to_s : sym
          return text.dup.freeze if text.is_a?(String) && text.match?(SYMBOL_FORMAT)

          @errors << "#{path} のシンボルは [a-zA-Z0-9_-] の文字列です: #{sym.inspect}"
          nil
        end

        def missing(path, empty = nil)
          @errors << "#{path} がありません"
          empty || GROUPS.keys.to_h { |g| [g, [].freeze] }.freeze
        end
      end
      private_constant :Parser
    end
  end
end
