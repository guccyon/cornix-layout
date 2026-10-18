# frozen_string_literal: true

require 'json'

# spec/fixtures の .vil（旧 compile が書いたもの）を、旧コードで求めて保存した 16bit 値
# （spec/fixtures/expected/<名前>.values.json）から DeviceImage にする。
# VilFile / VialNotation を通さない正解として ProfileMapper や VilFile の spec で使う。
#
#   VilImage.load('authors_baseline')   # spec/fixtures/authors_baseline.vil
#   VilImage.values('layout')           # 保存した値（Hash）
module VilImage
  module_function

  FIXTURES = File.expand_path('../../fixtures', __dir__)
  STRUCTURE_KEYS = %w[layout encoder_layout macro tap_dance combo settings].freeze
  NAMES = %w[layout authors_baseline].freeze

  def path(name) = File.join(FIXTURES, "#{name}.vil")

  def values(name) = JSON.parse(File.read(File.join(FIXTURES, 'expected', "#{name}.values.json")))

  def load(name)
    vil = JSON.parse(File.read(path(name), encoding: 'UTF-8'))
    v = values(name)
    Cornix::Image::DeviceImage.new(
      layers: v['layout'],
      encoders: v['encoder_layout'].map { |sides| sides.map { |ccw, cw| Cornix::Image::EncoderRecord.new(ccw: ccw, cw: cw) } },
      macros: v['macro'].map { |steps| steps.map { |step| macro_action(step) } },
      tap_dances: v['tap_dance'].map do |tap, hold, double, tap_hold, term|
        Cornix::Image::TapDanceRecord.new(on_tap: tap, on_hold: hold, on_double_tap: double, on_tap_hold: tap_hold,
                                          tapping_term: term)
      end,
      combos: v['combo'].map { |c| Cornix::Image::ComboRecord.new(keys: c[0, 4], output: c[4]) },
      settings: vil['settings'].to_h { |k, value| [Integer(k, 10), value] },
      meta: vil.reject { |k, _| STRUCTURE_KEYS.include?(k) }
    )
  end

  def macro_action(step)
    kind, *args = step
    case kind
    when 'delay', 'text' then Cornix::Image::MacroAction.new(kind: kind.to_sym, value: args.first)
    else Cornix::Image::MacroAction.new(kind: kind.to_sym, keys: args)
    end
  end
end
