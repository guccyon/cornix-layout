# frozen_string_literal: true

require_relative 'layer_action'
require_relative 'layer_tap'
require_relative 'layer_mod'

module Cornix
  module Domain
    module Keycode
      # レイヤーを指すキーコードの型（MO / TG / TO / OSL / TT / DF / PDF、LT、LM）。どれも #layer で LayerRef を返す。
      # Raw として読まれた値（基本キーでない base の LT、FN_MO13 / FN_MO23 など）は含まない
      LAYER_REF_TYPES = [LayerAction, LayerTap, LayerMod].freeze

      # keycode が指すレイヤーの番号。レイヤー操作でなければ nil
      def self.layer_index(keycode)
        keycode.layer.index if LAYER_REF_TYPES.any? { |type| keycode.is_a?(type) }
      end
    end
  end
end
