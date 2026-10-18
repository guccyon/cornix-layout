# frozen_string_literal: true

require_relative '../keycode'
require_relative '../checks'
require_relative '../layer_ref'
require_relative '../modifier_set'
require_relative 'basic'

module Cornix
  module Domain
    module Keycode
      # タップで基本キー、ホールドでレイヤー（QMK の LT、0x4000〜0x4FFF。レイヤーは 0〜15）
      class LayerTap < Data.define(:layer, :base)
        include Value
        LAYERS = (0..15)

        def initialize(layer:, base:)
          Checks.instance!(layer, LayerRef, 'レイヤー')
          Checks.integer!(layer.index, LAYERS, 'LT のレイヤー番号')
          Checks.instance!(base, Basic, 'タップのキー')
          super
        end
      end
    end
  end
end
