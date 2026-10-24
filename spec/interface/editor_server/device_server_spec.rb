# frozen_string_literal: true

require 'spec_helper'
require_relative '../../support/device_protocol_fixtures'

# device のサーバー（cornix serve --device）の、適合テストのデータでは確かめにくいこと
# （実機に書いた結果・バックアップのファイル・進み具合の並び・パイプでの取り消し・振り分け）
RSpec.describe 'device のサーバー' do
  let(:keys) do
    [{ 'layer' => 0, 'row' => 0, 'col' => 1, 'value' => 'KC_A' }, { 'layer' => 0, 'row' => 4, 'col' => 0, 'value' => 'KC_NO' },
     { 'layer' => 1, 'row' => 2, 'col' => 6, 'value' => 'KC_B' }]
  end
  let(:token) { '828ecd9225e5c798' } # spec/fixtures/protocol/device/device_apply/applies.json と同じ

  def fixture(data) = ProtocolFixtures::Fixture.new(path: 'device.json', data: data)

  def run(data, &) = DeviceProtocolFixtures.run(fixture(data), &)

  def compiled_image(run_result)
    vil = File.join(run_result.root, 'tmp/profiles/default/build/layout.vil')
    Cornix::Application::Environment.new(root: run_result.root).vil_file.read(vil)
  end

  def apply_data(device: {}, after: [])
    { 'setup' => { 'profile' => 'test_config', 'allowWrites' => true, 'device' => { 'from' => 'profile', 'keys' => keys }.merge(device) },
      'request' => { 'id' => 1, 'method' => 'device/apply', 'params' => { 'dir' => 'profiles/default', 'token' => token } },
      'after' => after }
  end

  it 'device/apply は実機をプロファイルの状態にし、書く前の状態を pre-apply のバックアップに残す' do
    run(apply_data) do |r|
      result = r.outcome.response.fetch('result')
      expect(result['backup']).to match(%r{\Atmp/profiles/default/snapshots/\d{8}-\d{6}-pre-apply(-\d+)?/layout\.vil\z})
      expect(r.device.keymap[0][0][1]).to eq(0x14) # KC_Q
      expect(r.device.keymap[0][4][0]).to eq(0x2A) # KC_BSPACE
      expect(Cornix::Application::Environment.new(root: r.root).vil_file.read(File.join(r.root, result['backup'])).layers[0][0][1])
        .to eq(0x04) # 書く前は KC_A
      expect(r.device.keymap).to eq(compiled_image(r).layers.map { |rows| rows.map { |cols| cols.map { |v| v || 0 } } })
    end
  end

  it '進み具合は read → write → verify の順で、段階ごとに done が total まで増える' do
    run(apply_data) do |r|
      progress = r.outcome.notifications.map { |m| m.fetch('params') }
      expect(progress.map { |p| p['phase'] }.chunk_while { |a, b| a == b }.map(&:first)).to eq(%w[read write verify])
      progress.group_by { |p| p['phase'] }.each do |phase, list|
        expect(list.map { |p| p['done'] }).to eq(list.map { |p| p['done'] }.sort), phase
        expect(list.last['done']).to eq(list.last['total']), phase
        expect(list.map { |p| p['total'] }.uniq.size).to eq(1), phase
      end
      expect(progress.select { |p| p['phase'] == 'write' }.map { |p| p['done'] }).to eq([1, 2, 3])
    end
  end

  it '読む間に取り消した device/apply は何も書かない' do
    run(apply_data(after: [{ 'method' => '$/cancelRequest', 'params' => { 'id' => 1 } }])) do |r|
      expect(r.outcome.response.dig('error', 'code')).to eq(-32_800)
      expect(r.device.writes).to be_empty
      expect(Dir.glob(File.join(r.root, 'tmp/profiles/default/snapshots/*-pre-apply'))).to be_empty
    end
  end

  it '書いている途中で切れたら -32072 の data にワークスペースからのバックアップのパスを入れる' do
    run(apply_data(device: { 'failWriteAfter' => 1 })) do |r|
      data = r.outcome.response.dig('error', 'data')
      expect(data['applied']).to eq(1)
      expect(data['backup']).to match(%r{\Atmp/profiles/default/snapshots/\d{8}-\d{6}-pre-apply(-\d+)?/layout\.vil\z})
      expect(File).to exist(File.join(r.root, data['backup']))
    end
  end

  it 'device/restore はバックアップの状態に戻し、戻す前の状態を pre-restore に残す' do
    data = {
      'setup' => { 'profile' => 'test_config', 'allowWrites' => true, 'device' => { 'from' => 'profile' },
                   'snapshots' => { '20261021-101500-pre-apply' => { 'from' => 'profile', 'keys' => [keys.first] } } },
      'request' => { 'id' => 1, 'method' => 'device/restore',
                     'params' => { 'dir' => 'profiles/default', 'backup' => '20261021-101500-pre-apply', 'token' => '68fbf3809474f4a4' } }
    }
    run(data) do |r|
      expect(r.outcome.response.dig('result', 'backup')).to match(/-pre-restore/)
      expect(r.device.keymap[0][0][1]).to eq(0x04)
    end
  end

  it 'パイプの入力でも、読む間に届いた $/cancelRequest を拾う（待たずに読む）' do
    Dir.mktmpdir do |root|
      FileUtils.cp_r(File.join(ProtocolFixtures::FIXTURES, 'test_config'), File.join(root, 'profiles', 'default').tap { |d| FileUtils.mkdir_p(File.dirname(d)) })
      device = FakeCornixDevice.new
      env_factory = ->(ws) { Cornix::Application::Environment.for(ws, device_opener: FakeCornixDevice.opener(device)) }
      ops = Cornix::Application::Editor::DeviceOperations.new(root: root, env_factory: env_factory)
      framing = Cornix::Interface::EditorServer::Framing
      reader, writer = IO.pipe
      [{ jsonrpc: '2.0', id: 0, method: 'initialize', params: { protocolVersion: '0.5' } },
       { jsonrpc: '2.0', id: 1, method: 'device/compare', params: { dir: 'profiles/default' } },
       { jsonrpc: '2.0', method: '$/cancelRequest', params: { id: 1 } },
       { jsonrpc: '2.0', id: 2, method: 'shutdown' }, { jsonrpc: '2.0', method: 'exit' }].each { |m| framing.write(writer, m) }
      writer.close
      output = StringIO.new(+'')
      code = Cornix::Interface::EditorServer::Server.new(device: ops, input: reader, output: output, error: StringIO.new).run
      output.rewind
      received = []
      while (m = framing.read(output))
        received << m
      end
      responses = received.reject { |m| m.key?('method') }
      expect(code).to eq(0)
      expect(responses.map { |m| m['id'] }).to eq([0, 1, 2]) # ためておいた shutdown も処理する
      expect(responses[1].dig('error', 'code')).to eq(-32_800)
    end
  end

  it '編集のサーバーと device のサーバーは別々のメソッドを振り分ける' do
    handler = Cornix::Interface::EditorServer::Handler
    device = handler.registry(:device).keys
    editor = handler.registry(:editor).keys
    expect(device).to contain_exactly('initialize', 'initialized', 'shutdown', 'exit', '$/cancelRequest', 'device/compare',
                                      'device/apply', 'device/backups', 'device/compareBackup', 'device/restore')
    expect(editor).to include('profile/open', 'initialize')
    expect(editor.grep(%r{\Adevice/})).to be_empty
    expect(handler.fetch('device/compare')).to be_nil
    expect(handler.fetch('device/compare', server: :device)).to eq(Cornix::Interface::EditorServer::Handlers::DeviceCompare)
  end

  it 'Server は workbench と device のどちらか一方を受け取る' do
    expect { Cornix::Interface::EditorServer::Server.new }.to raise_error(ArgumentError)
  end
end
