# frozen_string_literal: true

require 'spec_helper'
require_relative 'support/domain_factories'

RSpec.describe Cornix::Domain::ProfileDiagnostics do
  include DomainFactories

  let(:caps) { d::Capabilities::CORNIX }
  let(:tab) { key_position(:left, 0, 0) }

  def diagnostics_of(profile, capabilities = caps) = described_class.new(profile, capabilities).call

  def summary(diags) = diags.map { |x| [x.severity, x.path] }

  it '問題がなければ空で、結果は freeze されている' do
    result = diagnostics_of(build_profile)
    expect(result).to eq([])
    expect(result).to be_frozen
  end

  describe 'レイヤー' do
    it '枚数がレイヤー数を超えれば error' do
      layers = Array.new(11) { |i| build_layer(index: i) }
      diags = diagnostics_of(build_profile(layers: layers))
      expect(summary(diags)).to include([:error, 'layers'], [:error, 'layers[10].index'])
      expect(diags.find { |x| x.path == 'layers' }.message).to include('10 枚まで')
    end

    it '番号がレイヤー数以上なら error' do
      layers = Array.new(10) { |i| build_layer(index: i) }
      layers[9] = build_layer(index: 12)
      expect(summary(diagnostics_of(build_profile(layers: layers)))).to include([:error, 'layers[9].index'])
    end

    it '番号の重複は 2 件目以降が error' do
      diags = diagnostics_of(build_profile(layers: [build_layer(index: 0), build_layer(index: 1), build_layer(index: 1)]))
      expect(summary(diags)).to eq([[:error, 'layers[2].index']])
      expect(diags.first.message).to include('重複')
    end

    it '番号の抜けは warning' do
      diags = diagnostics_of(build_profile(layers: [build_layer(index: 0), build_layer(index: 3)]))
      expect(summary(diags)).to eq([[:warning, 'layers']])
      expect(diags.first.message).to include('1, 2')
    end
  end

  shared_examples '番号付きの集まり' do |key, what|
    it "件数の上限を超えれば error（#{what}）" do
      items = Array.new(33) { |i| build(index: i, name: "n#{i}") }
      diags = diagnostics_of(build_profile(key => items))
      expect(summary(diags)).to include([:error, key.to_s], [:error, "#{key}[32].index"])
    end

    it "番号が上限以上なら error（#{what}）" do
      diags = diagnostics_of(build_profile(key => [build(index: 32, name: 'a')]))
      expect(summary(diags)).to include([:error, "#{key}[0].index"])
      expect(diags.first.message).to include('0〜31')
    end

    it "番号の重複は error（#{what}）" do
      diags = diagnostics_of(build_profile(key => [build(index: 1, name: 'a'), build(index: 1, name: 'b')]))
      expect(summary(diags)).to include([:error, "#{key}[1].index"])
    end

    it "名前の重複は error（#{what}）" do
      diags = diagnostics_of(build_profile(key => [build(index: 0, name: 'Same'), build(index: 1, name: 'Same')]))
      expect(summary(diags)).to include([:error, "#{key}[1].name"])
      expect(diags.find { |x| x.path == "#{key}[1].name" }.message).to include('Same')
    end
  end

  describe 'マクロ' do
    def build(index:, name:) = build_macro(index: index, name: name)

    it_behaves_like '番号付きの集まり', :macros, 'マクロ'
  end

  describe 'タップダンス' do
    def build(index:, name:) = build_tap_dance(index: index, name: name)

    it_behaves_like '番号付きの集まり', :tap_dances, 'タップダンス'
  end

  describe 'コンボ' do
    def build(index:, name:) = build_combo(index: index, name: name)

    it_behaves_like '番号付きの集まり', :combos, 'コンボ'

    it 'トリガーの数が上限を超えれば error' do
      keys = Array.new(5) { |i| basic(0x04 + i) }
      layer = build_layer(keys: keys.each_with_index.to_h { |kc, i| [key_position(:left, 1, i), kc] })
      diags = diagnostics_of(build_profile(layers: [layer], combos: [build_combo(trigger_keys: keys)]))
      expect(summary(diags)).to eq([[:error, 'combos[0].trigger_keys']])
      expect(diags.first.message).to include('4 個まで')
    end

    describe '押せないコンボ' do
      let(:a) { key_position(:left, 1, 1) }
      let(:s) { key_position(:left, 1, 2) }

      it 'トリガーのキーがすべてそろうレイヤーがなければ warning（path は trigger_keys）' do
        layers = [build_layer(index: 0, keys: { a => basic(0x04) }), build_layer(index: 1, keys: { s => basic(0x16) })]
        diags = diagnostics_of(build_profile(layers: layers, combos: [build_combo(trigger_keys: [basic(0x04), basic(0x16)])]))
        expect(summary(diags)).to eq([[:warning, 'combos[0].trigger_keys']])
        expect(diags.first.message).to include('押せないコンボです')
      end

      it 'KC_TRNS の位置はレイヤー 0 の値で見る。トリガーが KC_NO だけなら警告しない' do
        layers = [build_layer(index: 0, keys: { a => basic(0x04) }),
                  build_layer(index: 1, keys: { a => k::TRANSPARENT, s => basic(0x16) })]
        combos = [build_combo(index: 0, trigger_keys: [basic(0x04), basic(0x16)]),
                  build_combo(index: 1, name: 'New', trigger_keys: [k::NO_KEY, k::NO_KEY])]
        expect(diagnostics_of(build_profile(layers: layers, combos: combos))).to eq([])
      end
    end
  end

  describe 'キーコードの参照' do
    it 'レイヤーのキーが存在しないマクロ・タップダンスを指せば error（パスは position_map のシンボル）' do
      layer = build_layer(keys: { tab => macro_call(5), key_position(:right, 3, 3) => td_call(2) })
      diags = diagnostics_of(build_profile(layers: [layer]))
      expect(summary(diags)).to eq([[:error, 'layers[0].left_hand.row0.tab'], [:error, 'layers[0].right_hand.thumb_keys.left']])
      expect(diags.map(&:message)).to eq(['マクロ M5 が定義されていません', 'タップダンス TD(2) が定義されていません'])
    end

    it 'カスタマイズした position_map のシンボルでパスを作る' do
      hash = position_map_hash.tap { |h| h['left_hand']['row3'] = %w[caps fn option] }
      layer = build_layer(keys: { key_position(:left, 3, 1) => macro_call(1) })
      diags = diagnostics_of(build_profile(layers: [layer], position_map: d::PositionMap.from_h(hash)))
      expect(diags.map(&:path)).to eq(['layers[0].left_hand.row3.fn'])
    end

    it '定義済みのマクロ・タップダンスを指していれば問題なし' do
      layer = build_layer(keys: { tab => macro_call(1) }, encoders: { left: encoder_binding(push: td_call(3)), right: encoder_binding })
      profile = build_profile(layers: [layer], macros: [build_macro(index: 1)], tap_dances: [build_tap_dance(index: 3)])
      expect(diagnostics_of(profile)).to eq([])
    end

    it 'エンコーダ、マクロのキー、タップダンスの動作、コンボのトリガーと出力も検査する' do
      layer = build_layer(encoders: { left: encoder_binding(cw: macro_call(9)), right: encoder_binding(push: td_call(9)) })
      macro = build_macro(index: 0, steps: [d::MacroStep::Delay.new(ms: 10), d::MacroStep::Tap.new(keys: [basic(4), macro_call(9)])])
      td = build_tap_dance(index: 0, on_hold: td_call(9))
      combo = build_combo(index: 0, trigger_keys: [basic(4), td_call(8)], output_key: macro_call(7))
      paths = diagnostics_of(build_profile(layers: [layer], macros: [macro], tap_dances: [td], combos: [combo])).map(&:path)
      expect(paths).to eq(%w[
        combos[0].trigger_keys
        layers[0].encoders.left.cw layers[0].encoders.right.push macros[0].steps[1].keys[1]
        tap_dances[0].on_hold combos[0].trigger_keys[1] combos[0].output_key
      ])
    end

    it 'レイヤー番号がレイヤー数以上なら error、定義されていないレイヤーなら warning' do
      layer_tap = k::LayerTap.new(layer: layer_ref(10), base: basic(0x2C))
      layer_mod = k::LayerMod.new(layer: layer_ref(2), mods: Cornix::Domain::ModifierSet.new(side: :left, mods: [:shift]))
      layer = build_layer(keys: { tab => mo(1), key_position(:left, 0, 1) => layer_tap, key_position(:left, 0, 2) => layer_mod,
                                  key_position(:left, 0, 3) => mo(0) })
      diags = diagnostics_of(build_profile(layers: [layer]))
      expect(summary(diags)).to eq([[:warning, 'layers[0].left_hand.row0.tab'], [:error, 'layers[0].left_hand.row0.Q'],
                                    [:warning, 'layers[0].left_hand.row0.W']])
      expect(diags[1].message).to include('0〜9')
    end

    it 'キーは position_map の定義順に並ぶ' do
      layer = build_layer(keys: { key_position(:right, 0, 0) => macro_call(1), tab => macro_call(2) })
      expect(diagnostics_of(build_profile(layers: [layer])).map(&:path))
        .to eq(%w[layers[0].left_hand.row0.tab layers[0].right_hand.row0.Y])
    end
  end

  describe '対応していないキー' do
    let(:unsupported) { caps.with(unsupported_keycodes: { 0x7C79 => 'QK_REPEAT_KEY: 非対応です' }) }
    let(:repeat) { k::Quantum.new(code: 0x7C79) }

    it 'Capabilities#unsupported_keycodes にある特殊キーは warning（どこに書いても）' do
      layer = build_layer(keys: { tab => repeat }, encoders: { left: encoder_binding(cw: repeat), right: encoder_binding })
      macro = build_macro(steps: [d::MacroStep::Tap.new(keys: [repeat])])
      td = build_tap_dance(on_hold: repeat)
      combo = build_combo(trigger_keys: [k::NO_KEY], output_key: repeat)
      profile = build_profile(layers: [layer], macros: [macro], tap_dances: [td], combos: [combo])
      diags = diagnostics_of(profile, unsupported)
      expect(summary(diags)).to eq([[:warning, 'layers[0].left_hand.row0.tab'], [:warning, 'layers[0].encoders.left.cw'],
                                    [:warning, 'macros[0].steps[0].keys[0]'], [:warning, 'tap_dances[0].on_hold'],
                                    [:warning, 'combos[0].output_key']])
      expect(diags.first.message).to eq('QK_REPEAT_KEY: 非対応です（書き込みますが、押しても動かない可能性があります）')
    end

    it '表にない特殊キーや、表が空なら何も言わない' do
      layer = build_layer(keys: { tab => k::Quantum.new(code: 0x7C7B) })
      expect(diagnostics_of(build_profile(layers: [layer]), unsupported)).to eq([])
      expect(diagnostics_of(build_profile(layers: [build_layer(keys: { tab => repeat })]))).to eq([])
    end
  end

  it 'Capabilities を差し替えられる' do
    small = d::Capabilities.new(layers: 2, macros: 1, tap_dances: 1, combos: 1, combo_keys: 2)
    triggers = { tab => basic(4), key_position(:left, 0, 1) => basic(5), key_position(:left, 0, 2) => basic(6) }
    profile = build_profile(layers: [build_layer(index: 0, keys: triggers)], macros: [build_macro(index: 1)],
                            combos: [build_combo(trigger_keys: [basic(4), basic(5), basic(6)])])
    layer = build_layer(index: 0, keys: { tab => mo(2) })
    expect(summary(diagnostics_of(profile, small))).to eq([[:error, 'macros[0].index'], [:error, 'combos[0].trigger_keys']])
    expect(summary(diagnostics_of(build_profile(layers: [layer]), small))).to eq([[:error, 'layers[0].left_hand.row0.tab']])
  end
end
