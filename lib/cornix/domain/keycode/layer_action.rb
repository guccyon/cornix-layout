# frozen_string_literal: true

require_relative '../keycode'
require_relative '../checks'
require_relative '../layer_ref'
require_relative '../modifier_set'
require_relative 'basic'

module Cornix
  module Domain
    module Keycode
      # レイヤー操作（MO / TG / TO / DF / OSL / TT / PDF）
      class LayerAction < Data.define(:op, :layer)
        include Value
        OPS = %i[to momentary default toggle one_shot tap_toggle persistent_default].freeze

        def initialize(op:, layer:)
          Checks.one_of!(op, OPS, 'レイヤー操作')
          Checks.instance!(layer, LayerRef, 'レイヤー')
          super
        end
      end
    end
  end
end
