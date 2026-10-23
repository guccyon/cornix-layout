# frozen_string_literal: true

require 'spec_helper'
require 'yaml'

RSpec.describe Cornix::Mapping::KeycodeCodec do
  subject(:codec) { described_class.new }

  let(:k) { Cornix::Domain::Keycode }
  let(:mods) { ->(side, *m) { Cornix::Domain::ModifierSet.new(side: side, mods: m) } }
  let(:basic) { ->(code) { k::Basic.new(code: code) } }
  let(:layer) { ->(i) { Cornix::Domain::LayerRef.new(index: i) } }

  # 旧 device/via_keycodes.yaml（vial-gui から抽出し実機で確認した表）を正解として使う。
  # M128〜M255（0x7780〜0x77FF）は vial-qmk ではマクロではなく QK_CONNECTION（OU_AUTO など）なので除く
  let(:vial_table) do
    YAML.load_file(File.expand_path('../fixtures/vial_keycodes_v6.yaml', __dir__))['codes']
        .reject { |name, code| name.end_with?('(kc)') || (0x7780..0x77FF).cover?(code) }
  end

  describe 'Vial の表のすべての値' do
    it 'Raw 以外に解釈でき、同じ値に戻る' do
      raws = []
      vial_table.each do |name, code|
        keycode = codec.decode(code)
        raws << name if keycode.is_a?(k::Raw)
        expect(codec.encode(keycode)).to eq(code), "#{name} (#{format('0x%04X', code)})"
      end
      expect(raws).to be_empty
    end
  end

  describe '#decode' do
    it '構造を持つ値に分解する' do
      expect(codec.decode(0x0000)).to eq(k::NO_KEY)
      expect(codec.decode(0x0001)).to eq(k::TRANSPARENT)
      expect(codec.decode(0x0004)).to eq(basic.(0x04))
      expect(codec.decode(0x0A21)).to eq(k::Modified.new(mods: mods.(:left, :gui, :shift), base: basic.(0x21)))
      expect(codec.decode(0x2890)).to eq(k::ModTap.new(mods: mods.(:left, :gui), base: basic.(0x90)))
      expect(codec.decode(0x412C)).to eq(k::LayerTap.new(layer: layer.(1), base: basic.(0x2C)))
      expect(codec.decode(0x5022)).to eq(k::LayerMod.new(layer: layer.(1), mods: mods.(:left, :shift)))
      expect(codec.decode(0x5223)).to eq(k::LayerAction.new(op: :momentary, layer: layer.(3)))
      expect(codec.decode(0x5289)).to eq(k::LayerAction.new(op: :one_shot, layer: layer.(9)))
      expect(codec.decode(0x52A2)).to eq(k::OneShotMod.new(mods: mods.(:left, :shift)))
      expect(codec.decode(0x5704)).to eq(k::TapDanceCall.new(index: 4))
      expect(codec.decode(0x7702)).to eq(k::MacroCall.new(index: 2))
      expect(codec.decode(0x7C00)).to eq(k::Quantum.new(code: 0x7C00))
    end

    it '解釈できない値は Raw として保持する' do
      expect(codec.decode(0x00E8)).to eq(k::Raw.new(code: 0x00E8))
      expect(codec.decode(0x1000)).to eq(k::Raw.new(code: 0x1000))
      expect(codec.decode(0xFFFF)).to eq(k::Raw.new(code: 0xFFFF))
    end

    it 'マクロは 0x7700〜0x777F（vial-qmk の QK_MACRO）。0x7780〜 は QK_CONNECTION' do
      expect(codec.decode(0x777F)).to eq(k::MacroCall.new(index: 127))
      expect(codec.decode(0x7780)).to eq(k::Quantum.new(code: 0x7780))
      expect(codec.decode(0x77FF)).to eq(k::Raw.new(code: 0x77FF))
    end

    it '修飾キーの書き方の順序に依存しない' do
      expect(mods.(:left, :shift, :gui)).to eq(mods.(:left, :gui, :shift))
    end
  end

  describe '#encode' do
    it 'カタログにない基本キーは UnknownKeycode' do
      expect { codec.encode(basic.(0xE8)) }.to raise_error(Cornix::UnknownKeycode)
    end

    it 'Raw はそのままの値' do
      expect(codec.encode(k::Raw.new(code: 0x1234))).to eq(0x1234)
    end
  end

  describe '#layer_of / #with_layer' do
    it '16bit 値の中のレイヤーの番号（LT / LM / レイヤー操作。基本キーでない LT の Raw も）を読み、付け替える' do
      { 0x5221 => 1, 0x52FF => 31, 0x4204 => 2, 0x4100 => 1, 0x50E1 => 7, 0x5200 => 0 }.each do |code, layer|
        expect(codec.layer_of(code)).to eq(layer)
      end
      [0x0004, 0x7700, 0x5700, 0x52A2, 0x2104].each { |code| expect(codec.layer_of(code)).to be_nil }
      expect(codec.with_layer(0x5221, 3)).to eq(0x5223)
      expect(codec.with_layer(0x4204, 9)).to eq(0x4904)
      expect(codec.with_layer(0x50E1, 2)).to eq(0x5041)
      expect(codec.with_layer(0x4204, 16)).to be_nil
      expect(codec.with_layer(0x7700, 1)).to be_nil
    end
  end
end
