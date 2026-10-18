# frozen_string_literal: true

require 'yaml'

# spec/domain で使う値の組み立て
module DomainFactories
  D = Cornix::Domain
  K = Cornix::Domain::Keycode

  def d = D
  def k = K

  DEFAULT_POSITION_MAP = File.expand_path('../../../lib/cornix/position_map.yaml', __dir__)

  def position_map_hash = YAML.load_file(DEFAULT_POSITION_MAP)
  def position_map = D::PositionMap.from_h(position_map_hash)

  def basic(code) = K::Basic.new(code: code)
  def layer_ref(index) = D::LayerRef.new(index: index)
  def mo(index) = K::LayerAction.new(op: :momentary, layer: layer_ref(index))
  def macro_call(index) = K::MacroCall.new(index: index)
  def td_call(index) = K::TapDanceCall.new(index: index)

  def key_position(hand, row, col) = D::KeyPosition.new(hand: hand, row: row, col: col)

  def encoder_binding(push: K::NO_KEY, ccw: K::NO_KEY, cw: K::NO_KEY)
    D::EncoderBinding.new(push: push, ccw: ccw, cw: cw)
  end

  def encoders = { left: encoder_binding, right: encoder_binding }

  def build_layer(index: 0, name: "Layer #{index}", keys: {}, encoders: self.encoders, description: nil)
    D::Layer.new(index: index, name: name, keys: keys, encoders: encoders, description: description)
  end

  def build_macro(index: 0, name: "Macro #{index}", steps: [D::MacroStep::Tap.new(keys: [basic(0x04)])])
    D::Macro.new(index: index, name: name, steps: steps)
  end

  def build_tap_dance(index: 0, name: "TapDance #{index}", on_tap: basic(0x04), on_hold: K::NO_KEY,
                      on_double_tap: K::NO_KEY, on_tap_hold: K::NO_KEY, tapping_term: 200)
    D::TapDance.new(index: index, name: name, on_tap: on_tap, on_hold: on_hold, on_double_tap: on_double_tap,
                    on_tap_hold: on_tap_hold, tapping_term: tapping_term)
  end

  def build_combo(index: 0, name: "Combo #{index}", trigger_keys: [basic(0x0E), basic(0x0F)], output_key: basic(0x2F))
    D::Combo.new(index: index, name: name, trigger_keys: trigger_keys, output_key: output_key)
  end

  def build_metadata = D::Metadata.new(keyboard: 'cornix', version: 1)

  def build_profile(layers: [build_layer], macros: [], tap_dances: [], combos: [], position_map: self.position_map)
    D::Profile.new(metadata: build_metadata, settings: D::QmkSettings::EMPTY, position_map: position_map,
                   layers: layers, macros: macros, tap_dances: tap_dances, combos: combos)
  end
end
