# frozen_string_literal: true

require 'spec_helper'
require_relative 'device_environment_context'

RSpec.describe Cornix::Application::Environment do
  it '既定の場所は Cornix::ROOT の下' do
    env = described_class.new
    expect(env.root).to eq(Cornix::ROOT)
    expect(env.config_dir).to eq(File.join(Cornix::ROOT, 'config'))
    expect(env.layout_path).to eq(File.join(Cornix::ROOT, 'tmp', 'build', 'layout.vil'))
    expect(env.decompile_input).to eq(File.join(Cornix::ROOT, 'tmp', 'layout.vil'))
    expect(env.backup_dir).to eq(File.join(Cornix::ROOT, 'tmp', 'device_backups'))
  end

  it '場所は root から決まり、個別に上書きできる' do
    env = described_class.new(root: '/r', layout_path: '/x/a.vil')
    expect(env.config_dir).to eq('/r/config')
    expect(env.layout_path).to eq('/x/a.vil')
    expect(env.backup_store.dir).to eq('/r/tmp/device_backups')
  end

  it '部品は一度だけ作る' do
    env = described_class.new
    expect(env.vil_file).to be(env.vil_file)
    expect(env.vil_file.vial).to be(env.vial)
    expect(env.codec).to be_a(Cornix::Mapping::KeycodeCodec)
    expect(env.notation).to be_a(Cornix::Mapping::KeycodeNotation)
    expect(env.mapper).to be_a(Cornix::Mapping::ProfileMapper)
    expect(env.describer).to be(env.describer)
  end

  it 'describer はキーコードを .vil の表記で、.vil で 16 進になる値は設定ファイルの表記で書く' do
    describer = described_class.new.describer
    expect(describer.keycode(0x0204)).to eq('LSFT(KC_A)')
    expect(describer.keycode(0x5203)).to eq('TO(3)')
    expect(describer.keycode(0x0C04)).to eq('Option + Command + A') # LAG(KC_A)
    expect(describer.keycode(0x7728)).to eq('M40')
    expect(describer.keycode(0x7E10)).to eq('USER16')
    expect(describer.keycode(0x7E40)).to eq('0x7e40')
  end

  describe '#open_device' do
    include_context 'device environment'

    it 'opener の Session をブロックに渡し、ブロックの戻り値を返す' do
      expect(env.open_device { |session| session.dims[:layers] }).to eq(FakeRmkDevice::LAYERS)
      expect(opens.size).to eq(1)
    end

    it 'ブロックがなければ ArgumentError' do
      expect { env.open_device }.to raise_error(ArgumentError)
    end

    it 'opener の例外はそのまま上がる' do
      env = described_class.new(root: @root, device_opener: ->(&_) { raise Cornix::DeviceError, 'Cornix が見つかりません' })
      expect { env.open_device { nil } }.to raise_error(Cornix::DeviceError, /見つかりません/)
    end
  end
end
