# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'
require 'stringio'
require_relative '../../lib/cornix/device/mcp_server'
require_relative 'fake_rmk_device'

RSpec.describe Cornix::Device::McpServer do
  let(:device) { FakeRmkDevice.new }
  let(:opener) do
    lambda do |&block|
      protocol = Cornix::Device::Protocol.new(device)
      allow(protocol).to receive(:definition).and_return(FakeRmkDevice::DEFINITION)
      block.call(Cornix::Device::Keyboard.new(protocol))
    end
  end
  let(:server) { described_class.new(keyboard_opener: opener) }
  let(:dir) { Dir.mktmpdir }

  before { stub_const('Cornix::Device::Keyboard::BACKUP_DIR', File.join(dir, 'backups')) }
  after { FileUtils.rm_rf(dir) }

  def call(name, args = {})
    server.handle('jsonrpc' => '2.0', 'id' => 1, 'method' => 'tools/call',
                  'params' => { 'name' => name, 'arguments' => args })[:result]
  end

  it 'initialize と tools/list に応答する' do
    init = server.handle('jsonrpc' => '2.0', 'id' => 1, 'method' => 'initialize', 'params' => {})
    expect(init[:result][:capabilities]).to eq(tools: {})
    tools = server.handle('jsonrpc' => '2.0', 'id' => 2, 'method' => 'tools/list')[:result][:tools]
    expect(tools.map { |t| t[:name] }).to eq(%w[keyboard_info read_keymap backup list_backups apply_layout])
  end

  it '通知には応答しない' do
    expect(server.handle('jsonrpc' => '2.0', 'method' => 'notifications/initialized')).to be_nil
  end

  it 'stdio で JSON-RPC を処理する' do
    input = StringIO.new(%({"jsonrpc":"2.0","id":7,"method":"ping"}\n))
    output = StringIO.new
    described_class.new(input: input, output: output, keyboard_opener: opener).run
    expect(JSON.parse(output.string)).to eq('jsonrpc' => '2.0', 'id' => 7, 'result' => {})
  end

  describe 'apply_layout' do
    let(:vil_path) { File.join(dir, 'layout.vil') }

    before do
      snapshot = nil
      opener.call { |kb| snapshot = kb.snapshot }
      snapshot['layout'][0][0][1] = 'KC_B'
      File.write(vil_path, JSON.generate(snapshot))
    end

    it '既定は dry run で、差分と確認トークンを返し書き込まない' do
      text = call('apply_layout', 'vil_path' => vil_path)[:content][0][:text]
      expect(text).to include('レイヤー0 (0,1): KC_NO → KC_B')
      expect(text).to match(/confirm_token: \h{16}/)
      expect(device.writes).to be_empty
    end

    it 'confirm_token なしの書き込みは拒否する' do
      result = call('apply_layout', 'vil_path' => vil_path, 'dry_run' => false)
      expect(result[:isError]).to be true
      expect(device.writes).to be_empty
    end

    it 'dry run のトークンを付けると書き込み、検証結果を返す' do
      token = call('apply_layout', 'vil_path' => vil_path)[:content][0][:text][/confirm_token: (\h+)/, 1]
      text = call('apply_layout', 'vil_path' => vil_path, 'dry_run' => false, 'confirm_token' => token)[:content][0][:text]
      expect(text).to include('1 件を書き込みました')
      expect(text).to include('すべて一致しました')
      expect(device.keymap[0][0][1]).to eq(0x05)
    end
  end
end
