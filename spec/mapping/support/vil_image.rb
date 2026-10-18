# frozen_string_literal: true

require 'json'

# 旧 compile が書いた layout.vil を、旧 Cornix::Device::Keycodes#encode で整数にして DeviceImage にする
# （p2-vil の VilFile が入るまでの、ProfileMapper の検証用）
module VilImage
  module_function

  STRUCTURE_KEYS = %w[layout encoder_layout macro tap_dance combo settings].freeze

  # 旧 Device::Keycodes が知らないが、旧 compile がそのまま .vil に書いた QMK 名
  # （spec/fixtures/layout.vil のマクロにある）。QMK の LSFT(KC_9) / LSFT(KC_0)
  QMK_NAMES = { 'KC_LEFT_PAREN' => 0x0226, 'KC_RIGHT_PAREN' => 0x0227 }.freeze

  def load(path, keycodes: Cornix::Device::Keycodes.new)
    from_hash(JSON.parse(File.read(path)), keycodes: keycodes)
  end

  def from_hash(vil, keycodes:)
    enc = ->(v) { v == -1 || v.nil? ? nil : QMK_NAMES.fetch(v) { keycodes.encode(v) } }
    Cornix::Image::DeviceImage.new(
      layers: vil['layout'].map { |grid| grid.map { |row| row.map(&enc) } },
      encoders: vil['encoder_layout'].map do |sides|
        sides.map { |ccw, cw| Cornix::Image::EncoderRecord.new(ccw: enc.(ccw), cw: enc.(cw)) }
      end,
      macros: vil['macro'].map { |steps| steps.map { |step| macro_action(step, enc) } },
      tap_dances: vil['tap_dance'].map do |tap, hold, double, tap_hold, term|
        Cornix::Image::TapDanceRecord.new(on_tap: enc.(tap), on_hold: enc.(hold), on_double_tap: enc.(double),
                                          on_tap_hold: enc.(tap_hold), tapping_term: term)
      end,
      combos: vil['combo'].map { |c| Cornix::Image::ComboRecord.new(keys: c[0, 4].map(&enc), output: enc.(c[4])) },
      settings: vil['settings'].to_h { |k, v| [Integer(k), v] },
      meta: vil.reject { |k, _| STRUCTURE_KEYS.include?(k) }
    )
  end

  def macro_action(step, enc)
    kind, *args = step
    case kind
    when 'delay', 'text' then Cornix::Image::MacroAction.new(kind: kind.to_sym, value: args.first)
    else Cornix::Image::MacroAction.new(kind: kind.to_sym, keys: args.map(&enc))
    end
  end
end
