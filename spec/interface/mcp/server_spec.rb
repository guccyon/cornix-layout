# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require_relative '../../application/device_environment_context'

RSpec.describe Cornix::Interface::Mcp::Server do
  include_context 'device environment'

  let(:server) { described_class.new(env) }

  def call(name, args = {})
    server.handle('jsonrpc' => '2.0', 'id' => 1, 'method' => 'tools/call',
                  'params' => { 'name' => name, 'arguments' => args })[:result]
  end

  def text(result) = result[:content][0][:text]

  # 1 行 1 メッセージで送り、応答を JSON で返す
  def round_trip(*messages)
    input = StringIO.new(messages.map { |m| "#{JSON.generate(m)}\n" }.join)
    output = StringIO.new
    described_class.new(env, input: input, output: output).run
    expect(output.string).to be_ascii_only
    output.string.lines.map { |line| JSON.parse(line) }
  end

  it 'initialize と tools/list に応答する（旧 Device::McpServer と同じツール）' do
    init = server.handle('jsonrpc' => '2.0', 'id' => 1, 'method' => 'initialize', 'params' => {})
    expect(init[:result]).to include(protocolVersion: '2025-06-18', capabilities: { tools: {} },
                                     serverInfo: { name: 'cornix-device', version: Cornix::VERSION })
    expect(init[:result][:instructions]).to include('dry_run: true（既定）')
    tools = server.handle('jsonrpc' => '2.0', 'id' => 2, 'method' => 'tools/list')[:result][:tools]
    expect(tools.map { |t| t[:name] }).to eq(%w[keyboard_info read_keymap backup list_backups restore_backup apply_layout])
    apply = tools.find { |t| t[:name] == 'apply_layout' }
    expect(apply[:inputSchema][:properties].keys).to eq(%i[vil_path dry_run confirm_token])
    expect(apply[:inputSchema][:properties][:vil_path][:description]).to include(env.layout_path)
  end

  it '保存した tools/list と instructions を返す（spec/fixtures/expected/mcp_tools.json）' do
    old = JSON.parse(File.read(File.expand_path('../../fixtures/expected/mcp_tools.json', __dir__)))
    expect(Cornix::Interface::Mcp::ToolCatalog::INSTRUCTIONS).to eq(old['instructions'])
    tools = Cornix::Interface::Mcp::ToolCatalog.tools(default_vil: old['default_vil'])
    expect(JSON.parse(JSON.generate(tools))).to eq(old['tools'])
  end

  it '通知には応答せず、知らないメソッドはエラー' do
    expect(server.handle('jsonrpc' => '2.0', 'method' => 'notifications/initialized')).to be_nil
    expect(server.handle('jsonrpc' => '2.0', 'id' => 1, 'method' => 'nope')[:error][:code]).to eq(-32_601)
  end

  it 'JSON として読めない行には Parse error を返す' do
    output = StringIO.new
    described_class.new(env, input: StringIO.new("{oops\n\n"), output: output).run
    expect(JSON.parse(output.string)).to eq('jsonrpc' => '2.0', 'id' => nil,
                                            'error' => { 'code' => -32_700, 'message' => 'Parse error' })
  end

  it 'JSON-RPC の往復: initialize → tools/list → apply_layout の dry run → token を付けて書き込み' do
    vil = write_vil(File.join(@root, 'レイアウト.vil')) { |v| v['layout'][0][0][1] = 'KC_B' }
    responses = round_trip(
      { jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '2025-03-26' } },
      { jsonrpc: '2.0', method: 'notifications/initialized' },
      { jsonrpc: '2.0', id: 2, method: 'tools/list' },
      { jsonrpc: '2.0', id: 3, method: 'tools/call', params: { name: 'apply_layout', arguments: { vil_path: vil } } }
    )
    expect(responses.map { |r| r['id'] }).to eq([1, 2, 3])
    expect(responses[0]['result']['protocolVersion']).to eq('2025-03-26')
    expect(responses[1]['result']['tools'].size).to eq(6)
    dry = responses[2]['result']['content'][0]['text']
    expect(dry).to include("対象: #{vil}", '差分 1 件:', '  - レイヤー0 (0,1): KC_NO → KC_B')
    expect(device.writes).to be_empty

    token = dry[/confirm_token: (\h+)/, 1]
    responses = round_trip(
      { jsonrpc: '2.0', id: 4, method: 'tools/call',
        params: { name: 'apply_layout', arguments: { vil_path: vil, dry_run: false, confirm_token: token } } }
    )
    applied = responses[0]['result']['content'][0]['text']
    expect(applied).to eq("1 件を書き込みました。\n反映前のバックアップ: #{env.snapshot_store.latest(kind: 'pre-apply').path}\n" \
                          '読み戻して検証し、すべて一致しました。')
    expect(device.keymap[0][0][1]).to eq(0x05)
  end

  it 'ロケールが US-ASCII でも日本語を含む入力を UTF-8 として読む' do
    line = %({"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"apply_layout","arguments":{"vil_path":"#{@root}/存在しない.vil"}}}\n)
    input = StringIO.new(line.b.force_encoding(Encoding::US_ASCII))
    output = StringIO.new
    described_class.new(env, input: input, output: output).run
    expect(output.string).to be_ascii_only
    result = JSON.parse(output.string)['result']
    expect(result['isError']).to be(true)
    expect(result['content'][0]['text']).to start_with('エラー: ').and include('存在しない.vil')
  end

  describe 'apply_layout' do
    let(:vil_path) { write_vil { |v| v['layout'][0][0][1] = 'KC_B' } }

    it '既定は dry run で、vil_path の既定は compile の出力（tmp/build/layout.vil）' do
      vil_path
      result = text(call('apply_layout'))
      expect(result).to include("対象: #{env.layout_path}", 'confirm_token: ')
      expect(device.writes).to be_empty
    end

    it 'dry_run: false には confirm_token が必要' do
      result = call('apply_layout', 'vil_path' => vil_path, 'dry_run' => false)
      expect(result[:isError]).to be(true)
      expect(text(result)).to include('confirm_token が必要です')
      expect(device.writes).to be_empty
    end

    it 'token が違えば書き込まない' do
      result = call('apply_layout', 'vil_path' => vil_path, 'dry_run' => false, 'confirm_token' => 'stale')
      expect(text(result)).to include('変わっています')
      expect(device.writes).to be_empty
    end

    it '差分がなければその旨を返す' do
      path = write_vil(File.join(@root, 'same.vil')) { nil }
      expect(text(call('apply_layout', 'vil_path' => path))).to eq("対象: #{path}\nキーボードとの差分はありません。")
      token = Cornix::Application::DeviceDiff.new(env).call(vil_path: path).token
      result = call('apply_layout', 'vil_path' => path, 'dry_run' => false, 'confirm_token' => token)
      expect(text(result)).to eq('キーボードとの差分はなかったため、何も書き込んでいません。')
    end
  end

  it 'keyboard_info / read_keymap / backup / list_backups' do
    expect(JSON.parse(text(call('keyboard_info')))).to include('name' => 'Fake')
    expect(JSON.parse(text(call('read_keymap')))['layout'][0][0][0]).to eq('KC_A')
    path = File.join(@root, 'saved.vil')
    expect(text(call('read_keymap', 'save_path' => path))).to eq("保存しました: #{path}")
    expect(File).to exist(path)
    expect(text(call('list_backups', 'kind' => 'backup'))).to eq('スナップショットはありません')
    expect(text(call('backup'))).to eq("バックアップを保存しました: #{env.snapshot_store.latest(kind: 'backup').path}")
    backup = env.snapshot_store.latest(kind: 'backup')
    expect(text(call('list_backups', 'kind' => 'backup')))
      .to eq("#{backup.time.strftime('%Y-%m-%d %H:%M:%S')}  backup  #{backup.path}")
    expect(text(call('list_backups')).lines.size).to eq(3) # read_keymap で 2 回読んだ read と backup
    expect(text(call('list_backups', 'kind' => 'nope'))).to start_with('エラー: 知らないスナップショットの種類')
  end

  describe '2 つ目の content（結果の to_h の JSON。CLI の --json と同じ変換）' do
    def data(result) = JSON.parse(result[:content][1][:text])

    def cli_json(*argv)
      out = StringIO.new
      Cornix::Interface::Cli::Main.new(env_factory: ->(_ws) { env }, out: out, err: StringIO.new, input: StringIO.new)
                                  .run([*argv, '--json'])
      JSON.parse(out.string)
    end

    it 'apply_layout の dry run は cornix device diff --json と同じ。書き込みは ApplyOutcome#to_h' do
      vil = write_vil(File.join(@root, 'a.vil')) { |v| v['layout'][0][0][1] = 'KC_B' }
      dry = call('apply_layout', 'vil_path' => vil)
      expect(dry[:content].size).to eq(2)
      expect(data(dry)).to eq(cli_json('device', 'diff', vil))
      expect(data(dry)['changes']).to eq([{ 'description' => 'レイヤー0 (0,1): KC_NO → KC_B', 'kind' => 'set_keycode',
                                            'layer' => 0, 'row' => 0, 'col' => 1, 'from' => 0, 'to' => 0x05 }])

      applied = call('apply_layout', 'vil_path' => vil, 'dry_run' => false, 'confirm_token' => data(dry)['token'])
      expect(data(applied)).to include('written' => true, 'applied' => 1, 'success' => true,
                                       'backup' => env.snapshot_store.latest(kind: 'pre-apply').path)
    end

    it 'backup / list_backups / read_keymap（save_path あり）も to_h を付ける。keyboard_info は 1 つだけ' do
      expect(data(call('backup'))).to eq('path' => env.snapshot_store.latest(kind: 'backup').path)
      expect(data(call('list_backups', 'kind' => 'backup'))).to eq(cli_json('snapshots', '--kind', 'backup').except('config'))
      path = File.join(@root, 'saved.vil')
      expect(data(call('read_keymap', 'save_path' => path))).to include('path' => path)
      expect(call('keyboard_info')[:content].size).to eq(1)
      expect(call('read_keymap')[:content].size).to eq(1)
    end
  end

  it '不明なツールはエラー' do
    expect(text(call('nope'))).to eq('エラー: 不明なツール: nope')
  end

  it 'キーボードが接続されていないとき、各ツールはエラーを返す' do
    disconnected = Cornix::Application::Environment.new(
      root: @root, device_opener: ->(&_) { raise Cornix::DeviceError, 'Cornix が見つかりません' }
    )
    result = described_class.new(disconnected).handle('jsonrpc' => '2.0', 'id' => 1, 'method' => 'tools/call',
                                                      'params' => { 'name' => 'keyboard_info', 'arguments' => {} })[:result]
    expect(result[:isError]).to be(true)
    expect(text(result)).to include('見つかりません')
  end

  describe 'restore_backup' do
    it 'バックアップがないときはエラーを返す' do
      expect(call('restore_backup')[:isError]).to be(true)
    end

    it '書き込み後に直前の apply の前の状態（pre-apply）に戻せる。名前でも指定できる' do
      vil_path = write_vil(File.join(@root, 'layout.vil')) { |v| v['layout'][1][1][1] = 'KC_C' }
      token = text(call('apply_layout', 'vil_path' => vil_path))[/confirm_token: (\h+)/, 1]
      call('apply_layout', 'vil_path' => vil_path, 'dry_run' => false, 'confirm_token' => token)
      expect(device.keymap[1][1][1]).to eq(0x06)

      dry = text(call('restore_backup'))
      pre_apply = env.snapshot_store.latest(kind: 'pre-apply')
      expect(dry).to include("対象: #{pre_apply.path}", 'レイヤー1 (1,1): KC_C → KC_NO')
      expect(text(call('restore_backup', 'backup_path' => pre_apply.name))).to eq(dry)
      token = dry[/confirm_token: (\h+)/, 1]
      call('restore_backup', 'dry_run' => false, 'confirm_token' => token)
      expect(device.keymap[1][1][1]).to eq(0)
    end
  end
end
