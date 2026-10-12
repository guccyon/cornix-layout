# frozen_string_literal: true

require 'spec_helper'
require_relative '../../lib/cornix/device/protocol'
require_relative 'fake_rmk_device'

RSpec.describe Cornix::Device::Protocol do
  let(:device) { FakeRmkDevice.new }
  let(:protocol) { described_class.new(device) }
  let(:dims) { { layers: 2, rows: 2, cols: 3, encoders: 1 } }

  # ファームウェアに送ってはいけないコマンド
  FORBIDDEN = [0x06, 0x0A, 0x0B, 0x10, 0x13].freeze
  FORBIDDEN_VIAL = [0x06, 0x07, 0x08, 0x0C].freeze

  after do
    device.sent.each do |m|
      expect(FORBIDDEN).not_to include(m[0])
      expect(FORBIDDEN_VIAL).not_to include(m[1]) if m[0] == 0xFE
    end
  end

  describe '読み取り' do
    it 'プロトコル情報を読む' do
      expect(protocol.via_protocol_version).to eq(9)
      expect(protocol.keyboard_id).to eq(vial_protocol: 6, uid: 0x0807060504030201)
      expect(protocol.layer_count).to eq(2)
      expect(protocol.unlock_status).to eq(unlocked: false, in_progress: false, unlock_keys: [[1, 1], [1, 2]])
      expect(protocol.supported_settings).to eq([2, 7, 22])
      expect(protocol.setting(7)).to eq(200)
      expect(protocol.setting(22)).to eq(0)
    end

    it 'キーマップを 28 バイト以下の単位で読む' do
      expect(protocol.keymap_buffer(2, 2, 3)).to eq([4] + [0] * 11)
      expect(device.sent.select { |m| m[0] == 0x12 }.map { |m| m[3] }).to all(be <= 28)
    end

    it 'マクロバッファをサイズを超えて読まない' do
      protocol.macro_buffer(FakeRmkDevice::MACRO_SIZE, FakeRmkDevice::MACRO_COUNT)
      device.sent.select { |m| m[0] == 0x0E }.each do |m|
        expect(((m[1] << 8) | m[2]) + m[3]).to be <= FakeRmkDevice::MACRO_SIZE
      end
    end
  end

  describe '書き込みの範囲検査' do
    it '範囲内なら 1 キーずつ書き込む' do
      protocol.set_keycode(1, 1, 2, 0x0005, dims: dims)
      expect(device.keymap[1][1][2]).to eq(5)
    end

    it '範囲外の layer/row/col は送信せずに拒否する' do
      expect { protocol.set_keycode(2, 0, 0, 4, dims: dims) }.to raise_error(ArgumentError, /layer/)
      expect { protocol.set_keycode(0, 2, 0, 4, dims: dims) }.to raise_error(ArgumentError, /row/)
      expect { protocol.set_keycode(0, 0, 3, 4, dims: dims) }.to raise_error(ArgumentError, /col/)
      expect { protocol.set_encoder(0, 1, true, 4, dims: dims) }.to raise_error(ArgumentError, /encoder/)
      expect { protocol.set_tap_dance(2, [0, 0, 0, 0], 200, count: 2) }.to raise_error(ArgumentError)
      expect { protocol.set_combo(2, [0, 0, 0, 0], 0, count: 2) }.to raise_error(ArgumentError)
      expect(device.writes).to be_empty
    end

    it 'QK_BOOT などの boot 系キーコードは拒否する' do
      expect { protocol.set_keycode(0, 0, 0, 0x7C00, dims: dims) }.to raise_error(ArgumentError, /boot/)
      expect { protocol.set_encoder(0, 0, true, 0x7C01, dims: dims) }.to raise_error(ArgumentError, /boot/)
      expect(device.writes).to be_empty
    end

    it '未対応の設定や範囲外の値は拒否する' do
      expect { protocol.set_setting(99, 1) }.to raise_error(ArgumentError)
      expect { protocol.set_setting(22, 2) }.to raise_error(ArgumentError)
      expect { protocol.set_setting(7, 0x10000) }.to raise_error(ArgumentError)
      expect(device.writes).to be_empty
    end

    it 'マクロは先頭から 28 バイトずつ書き、バッファを超えるものは拒否する' do
      protocol.set_macro_buffer('a' * 40, size: FakeRmkDevice::MACRO_SIZE)
      sizes = device.sent.select { |m| m[0] == 0x0F }.map { |m| [((m[1] << 8) | m[2]), m[3]] }
      expect(sizes).to eq([[0, 28], [28, 12]])
      expect { protocol.set_macro_buffer('a' * 65, size: FakeRmkDevice::MACRO_SIZE) }.to raise_error(ArgumentError)
    end
  end
end
