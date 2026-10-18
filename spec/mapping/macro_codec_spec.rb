# frozen_string_literal: true

require 'spec_helper'
require 'json'
require_relative '../../lib/cornix/device/keycodes'
require_relative '../../lib/cornix/device/macro_codec'

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

  describe '旧 Device::MacroCodec との一致' do
    keycodes = Cornix::Device::Keycodes.new
    old = Cornix::Device::MacroCodec.new(keycodes)
    sources = [
      File.expand_path('../fixtures/layout.vil', __dir__),
      File.expand_path('../../../domain-architecture/tmp/baseline/layout.vil', __dir__)
    ].select { |path| File.exist?(path) }

    to_actions = lambda do |macro|
      macro.map do |tag, *args|
        case tag
        when 'tap', 'down', 'up'
          Cornix::Image::MacroAction.new(kind: tag.to_sym, keys: args.map { |k| keycodes.encode(k) })
        else
          Cornix::Image::MacroAction.new(kind: tag.to_sym, value: args.first)
        end
      end
    end

    sources.each do |path|
      it "#{File.basename(File.dirname(path))}/#{File.basename(path)} のマクロで同じバイト列と同じ解読結果になる" do
        # 旧 Device::Keycodes が知らない名前（KC_LEFT_PAREN など）を含むマクロは比較できないので空にする
        macros = JSON.parse(File.read(path, encoding: 'UTF-8')).fetch('macro').map do |m|
          old.encode(m)
          m
        rescue Cornix::Device::Keycodes::UnknownKeycode
          []
        end
        expect(macros.count { |m| !m.empty? }).to be >= 10
        buffer = codec.encode_all(macros.map { |m| to_actions.call(m) })
        expect(buffer).to eq(old.encode_all(macros))
        expect(codec.decode_all(buffer, macros.size)).to eq(old.decode_all(buffer, macros.size).map { |m| to_actions.call(m) })
      end
    end

    it '合成したマクロ（拡張コード・delay・ばらばらの tap）でも一致する' do
      macros = [
        [%w[tap KC_A], %w[tap KC_B], ['delay', 254], ['delay', 255], %w[down LSFT(KC_NO)], %w[up LSFT(KC_2)]],
        [['text', 'x'], ['text', 'y'], %w[tap LT1(KC_SPACE) MO(3)]]
      ]
      buffer = codec.encode_all(macros.map { |m| to_actions.call(m) })
      expect(buffer).to eq(old.encode_all(macros))
      expect(codec.decode_all(buffer, 2)).to eq(old.decode_all(buffer, 2).map { |m| to_actions.call(m) })
    end
  end
end
