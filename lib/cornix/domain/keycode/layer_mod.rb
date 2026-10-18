# frozen_string_literal: true

require_relative '../keycode'
require_relative '../checks'
require_relative '../layer_ref'
require_relative '../modifier_set'
require_relative 'basic'

module Cornix
  module Domain
    module Keycode
      # 修飾キーを押したままのレイヤー（QMK の LM、0x5000〜0x51FF。レイヤーは 0〜15）
      class LayerMod < Data.define(:layer, :mods)
        include Value
        LAYERS = (0..15)

        def initialize(layer:, mods:)
          Checks.instance!(layer, LayerRef, 'レイヤー')
          Checks.integer!(layer.index, LAYERS, 'LM のレイヤー番号')
          Checks.instance!(mods, ModifierSet, '修飾キー')
          super
        end
      end
    end
  end
end
