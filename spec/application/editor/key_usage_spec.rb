# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Cornix::Application::Editor::KeyUsage do
  let(:env) { Cornix::Application::Environment.new(config_dir: File.join(__dir__, '../../fixtures/test_config')) }
  let(:profile) { env.repository.load }
  let(:d) { Cornix::Domain }

  def kc(text) = env.notation.parse(text)
  def code(text) = env.codec.encode(kc(text))

  def binding(push, ccw, cw) = d::EncoderBinding.new(push: kc(push), ccw: kc(ccw), cw: kc(cw))

  # レイヤー 1 枚・マクロ・タップダンス・コンボを 1 つずつにしたプロファイル
  let(:small) do
    a, b, c = profile.position_map.positions.first(3)
    layer = d::Layer.new(index: 0, name: 'Base', keys: { a => kc('A'), b => kc('Trans'), c => kc('NoKey') },
                         encoders: { left: binding('Mute', 'Vol-', 'Vol+'), right: binding('A', 'NoKey', 'NoKey') })
    macro = d::Macro.new(index: 0, name: 'M', steps: [d::MacroStep::Tap.new(keys: [kc('A'), kc('B')]),
                                                      d::MacroStep::Delay.new(ms: 10), d::MacroStep::Down.new(keys: [kc('LShift')])])
    tap_dance = d::TapDance.new(index: 0, name: 'T', on_tap: kc('B'), on_hold: kc('MO(1)'), on_double_tap: kc('NoKey'),
                                on_tap_hold: kc('NoKey'), tapping_term: 200)
    combo = d::Combo.new(index: 0, name: 'C', trigger_keys: [kc('A'), kc('B'), kc('NoKey'), kc('NoKey')], output_key: kc('Escape'))
    profile.with(layers: [layer], macros: [macro], tap_dances: [tap_dance], combos: [combo])
  end

  it 'レイヤーのキーとエンコーダ・マクロの手順のキー・タップダンスの動作・コンボのトリガーと出すキーを 16bit 値で数える' do
    expect(described_class.count(small, env.codec)).to eq(
      code('A') => 4, code('B') => 3, code('Mute') => 1, code('Vol-') => 1, code('Vol+') => 1,
      code('LShift') => 1, code('MO(1)') => 1, code('Escape') => 1
    )
  end

  it 'KC_NO・KC_TRNS は数えない' do
    counts = described_class.count(profile, env.codec)
    expect(counts).not_to include(0x0000, 0x0001)
    expect(counts.values).to all(be_positive)
  end

  it 'プロファイルがなければ空' do
    expect(described_class.count(nil, env.codec)).to eq({})
  end
end
