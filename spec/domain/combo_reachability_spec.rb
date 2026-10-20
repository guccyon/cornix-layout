# frozen_string_literal: true

require 'spec_helper'
require_relative 'support/domain_factories'

RSpec.describe Cornix::Domain::ComboReachability do
  include DomainFactories

  let(:a) { key_position(:left, 1, 1) }
  let(:s) { key_position(:left, 1, 2) }
  let(:kc_a) { basic(0x04) }
  let(:kc_s) { basic(0x16) }
  let(:combo) { build_combo(trigger_keys: [kc_a, kc_s]) }

  def reachable?(layers, target = combo) = described_class.new(build_profile(layers: layers)).reachable?(target)

  it '1 つのレイヤーにトリガーのキーがすべてあれば押せる' do
    expect(reachable?([build_layer(index: 0, keys: { a => kc_a, s => kc_s })])).to be(true)
  end

  it 'トリガーのキーが別々のレイヤーにしかなければ押せない' do
    layers = [build_layer(index: 0, keys: { a => kc_a }), build_layer(index: 1, keys: { s => kc_s })]
    expect(reachable?(layers)).to be(false)
  end

  it 'KC_TRNS の位置はレイヤー 0 の値で見る（番号 0 のレイヤー。並びの先頭ではない）' do
    layers = [build_layer(index: 1, keys: { a => k::TRANSPARENT, s => kc_s }), build_layer(index: 0, keys: { a => kc_a })]
    expect(reachable?(layers)).to be(true)
    expect(reachable?([build_layer(index: 1, keys: { a => k::TRANSPARENT, s => kc_s })])).to be(false)
  end

  it 'エンコーダのプッシュ（マトリクスのキー）も数える' do
    layer = build_layer(index: 0, keys: { a => kc_a }, encoders: { left: encoder_binding(push: kc_s), right: encoder_binding })
    expect(reachable?([layer])).to be(true)
    layer = build_layer(index: 0, keys: { a => kc_a }, encoders: { left: encoder_binding(cw: kc_s), right: encoder_binding })
    expect(reachable?([layer])).to be(false)
  end

  it 'キーコードは値そのもので比べる（LT の位置では基本キーのトリガーはそろわない）' do
    lt = k::LayerTap.new(layer: layer_ref(1), base: kc_s)
    expect(reachable?([build_layer(index: 0, keys: { a => kc_a, s => lt })])).to be(false)
  end

  it 'トリガーの KC_NO は数えず、KC_NO だけなら押せる扱い' do
    layer = build_layer(index: 0, keys: { a => kc_a })
    expect(reachable?([layer], build_combo(trigger_keys: [kc_a, k::NO_KEY]))).to be(true)
    expect(reachable?([layer], build_combo(trigger_keys: [k::NO_KEY, k::NO_KEY]))).to be(true)
    expect(reachable?([], build_combo(trigger_keys: [k::NO_KEY]))).to be(true)
  end
end
