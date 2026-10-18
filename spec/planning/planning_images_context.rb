# frozen_string_literal: true

# spec/planning と spec/device で使う小さな DeviceImage（FakeRmkDevice と同じ形: 2 レイヤー × 2 行 × 3 列、(1,2) はキーなし）
RSpec.shared_context 'planning images' do
  def action(kind, *args)
    if %i[tap down up].include?(kind)
      Cornix::Image::MacroAction.new(kind: kind, keys: args)
    else
      Cornix::Image::MacroAction.new(kind: kind, value: args.first)
    end
  end

  def record(ccw, cw) = Cornix::Image::EncoderRecord.new(ccw: ccw, cw: cw)

  def td(tap, hold, double, tap_hold, term)
    Cornix::Image::TapDanceRecord.new(on_tap: tap, on_hold: hold, on_double_tap: double, on_tap_hold: tap_hold,
                                      tapping_term: term)
  end

  def combo(keys, output) = Cornix::Image::ComboRecord.new(keys: keys, output: output)

  let(:current) do
    Cornix::Image::DeviceImage.new(
      layers: [[[4, 0, 0], [0, 0, nil]], [[0, 0, 0], [0, 0, nil]]],
      encoders: [[record(0xAA, 0xA9)], [record(0xAA, 0xA9)]],
      macros: [[], [], [], []],
      tap_dances: [td(0, 0, 0, 0, 250), td(0, 0, 0, 0, 250)],
      combos: [combo([0, 0, 0, 0], 0), combo([0, 0, 0, 0], 0)],
      settings: { 2 => 50, 7 => 200, 22 => 0 },
      meta: { 'version' => 1, 'layout_options' => 0, 'alt_repeat_key' => [], 'key_override' => [] }
    )
  end
end
