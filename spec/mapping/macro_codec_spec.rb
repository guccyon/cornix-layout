# frozen_string_literal: true

require 'spec_helper'
require 'json'
require_relative 'support/vil_image'

RSpec.describe Cornix::Mapping::MacroCodec do
  subject(:codec) { described_class.new }

  def action(kind, *args)
    if %i[tap down up].include?(kind)
      Cornix::Image::MacroAction.new(kind: kind, keys: args)
    else
      Cornix::Image::MacroAction.new(kind: kind, value: args.first)
    end
  end

  it 'tap/down/up/text/delay を Vial と同じバイト列にする' do
    macro = [action(:down, 0xE1), action(:tap, 0x26, 0x27), action(:up, 0xE1), action(:text, 'ab'), action(:delay, 300)]
    expect(codec.encode(macro).bytes).to eq(
      [1, 2, 0xE1, 1, 1, 0x26, 1, 1, 0x27, 1, 3, 0xE1, 0x61, 0x62, 1, 4, 46, 2]
    )
  end

  it '16bit キーコードは拡張コードで、下位バイトが 0 の場合は 0xFF00 形式にする' do
    expect(codec.encode([action(:tap, 0x021F)]).bytes).to eq([1, 5, 0x1F, 0x02])
    expect(codec.encode([action(:tap, 0x0200)]).bytes).to eq([1, 5, 0x02, 0xFF])
    expect(codec.decode([1, 5, 0x02, 0xFF].pack('C*'))).to eq([action(:tap, 0x0200)])
    expect(codec.encode([action(:down, 0x0200), action(:up, 0x0200)]).bytes).to eq([1, 6, 0x02, 0xFF, 1, 7, 0x02, 0xFF])
  end

  it 'delay は 1 から始まる 2 バイトで表し、上限を超えると拒否する' do
    expect(codec.encode([action(:delay, 0)]).bytes).to eq([1, 4, 1, 1])
    expect(codec.decode(codec.encode([action(:delay, 65_024)]))).to eq([action(:delay, 65_024)])
    expect { codec.encode([action(:delay, 65_025)]) }.to raise_error(Cornix::InvalidValue)
  end

  it '連続する同じ種類のキー操作と text をまとめて読む' do
    bytes = [1, 1, 4, 1, 1, 5, 0x61, 0x62, 1, 2, 4, 1, 3, 4].pack('C*')
    expect(codec.decode(bytes)).to eq([action(:tap, 4, 5), action(:text, 'ab'), action(:down, 4), action(:up, 4)])
  end

  it '往復で同じマクロに戻り、空のマクロも NUL で区切る' do
    macros = [
      [action(:tap, 0x2F, 0x30, 0x50)],
      [action(:down, 0xE3), action(:tap, 0x06), action(:up, 0xE3), action(:tap, 0x4F)],
      [action(:text, 'hello'), action(:delay, 1000), action(:tap, 0x021F, 0x0200)],
      []
    ]
    buffer = codec.encode_all(macros)
    expect(buffer.count("\x00")).to eq(4)
    expect(codec.decode_all(buffer, 4)).to eq(macros)
    expect(codec.decode_all(''.b, 2)).to eq([[], []])
  end

  it 'UTF-8 の text はそのまま往復する' do
    expect(codec.decode(codec.encode([action(:text, 'あ')]))).to eq([action(:text, 'あ')])
  end

  it 'NUL や制御コード 1 を含む text、範囲外のキーコードは拒否する' do
    expect { codec.encode([action(:text, "a\x00b")]) }.to raise_error(Cornix::InvalidValue)
    expect { codec.encode([action(:text, "a\x01b")]) }.to raise_error(Cornix::InvalidValue)
    expect { codec.encode([action(:tap, 0x10000)]) }.to raise_error(Cornix::InvalidValue)
  end

  it '途中で切れた命令や知らない命令は旧実装と同じく読み飛ばす' do
    expect(codec.decode([1, 9, 0x61, 1].pack('C*'))).to eq([action(:text, 'a')])
  end

  # 旧 Device::MacroCodec が書いたバイト列（spec/fixtures/expected/macro_buffers.json に保存したもの）と比べる
  describe '旧 Device::MacroCodec との一致' do
    expected = JSON.parse(File.read(File.join(VilImage::FIXTURES, 'expected', 'macro_buffers.json')))
    to_actions = ->(macros) { macros.map { |m| m.map { |step| VilImage.macro_action(step) } } }

    VilImage::NAMES.each do |name|
      it "spec/fixtures/#{name}.vil のマクロで同じバイト列になり、解読すると元に戻る" do
        # 旧 Device::Keycodes が知らない名前（KC_LEFT_PAREN など）を含むマクロは旧コードで比較できなかったので空にする
        skipped = expected.dig(name, 'skipped')
        macros = VilImage.load(name).macros.each_with_index.map { |m, i| skipped.include?(i) ? [] : m }
        expect(macros.count { |m| !m.empty? }).to be >= 10
        buffer = codec.encode_all(macros)
        expect(buffer.unpack1('H*')).to eq(expected.dig(name, 'buffer'))
        expect(codec.decode_all(buffer, macros.size)).to eq(macros)
      end
    end

    it '合成したマクロ（拡張コード・delay・ばらばらの tap）でも一致する' do
      synthetic = expected.fetch('synthetic')
      buffer = codec.encode_all(to_actions.call(synthetic['macros']))
      expect(buffer.unpack1('H*')).to eq(synthetic['buffer'])
      expect(codec.decode_all(buffer, 2)).to eq(to_actions.call(synthetic['decoded']))
    end
  end
end
