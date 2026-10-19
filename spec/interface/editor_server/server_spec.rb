# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'tmpdir'

RSpec.describe Cornix::Interface::EditorServer::Server do
  def framing = Cornix::Interface::EditorServer::Framing
  handler = Cornix::Interface::EditorServer::Handler

  around do |example|
    Dir.mktmpdir('cornix-serve') do |dir|
      @root = dir
      example.run
    end
  end

  after { %w[test/fail test/boom test/missing test/config test/notify].each { |name| handler::REGISTRY.delete(name) } }

  let(:workbench) { Cornix::Application::Editor::Workbench.new(root: @root, env_factory: ->(ws) { ws }) }
  let(:error) { StringIO.new }
  let(:server) { described_class.new(workbench: workbench, input: StringIO.new, output: StringIO.new, error: error) }

  def request(id, method, params = nil)
    { 'jsonrpc' => '2.0', 'id' => id, 'method' => method }.tap { |m| m['params'] = params if params }
  end

  def notification(method, params = nil)
    { 'jsonrpc' => '2.0', 'method' => method }.tap { |m| m['params'] = params if params }
  end

  def initialize!(target = server)
    target.handle(request(0, 'initialize', { 'protocolVersion' => '0.1' }))
    target.handle(notification('initialized'))
  end

  # 枠で書いたメッセージを流して [終了コード, 読んだメッセージ] を返す
  def run_framed(*messages, raw: nil)
    input = StringIO.new(+'')
    messages.each { |m| framing.write(input, m) }
    input.write(raw) if raw
    input.rewind
    output = StringIO.new(+'')
    code = described_class.new(workbench: workbench, input: input, output: output, error: error).run
    output.rewind
    received = []
    while (m = framing.read(output))
      received << m
    end
    [code, received]
  end

  describe 'ライフサイクル' do
    it 'initialize の前のリクエストは -32002、通知は捨てる' do
      expect(server.handle(request(1, 'profile/list'))).to eq(jsonrpc: '2.0', id: 1, error: { code: -32_002, message: 'initialize の前です' })
      expect(server.handle(notification('profile/close', { 'profileId' => 'p1' }))).to be_nil
    end

    it 'initialize のあとは振り分け、shutdown の後のリクエストは -32600' do
      initialize!
      expect(server.handle(request(1, 'profile/list'))).to eq(jsonrpc: '2.0', id: 1, result: { profiles: [], default: nil })
      expect(server.handle(request(2, 'shutdown'))).to eq(jsonrpc: '2.0', id: 2, result: nil)
      expect(server.handle(request(3, 'profile/list'))[:error]).to include(code: -32_600)
      expect(server.handle(notification('initialized'))).to be_nil
    end

    it '版が合わない initialize のあとは初期化されていないまま' do
      response = server.handle(request(1, 'initialize', { 'protocolVersion' => '9.9' }))
      expect(response[:error]).to include(code: -32_051, data: { supported: ['0.1'] })
      expect(server.handle(request(2, 'profile/list'))[:error][:code]).to eq(-32_002)
    end

    it 'exit で run が終わり、shutdown を受けていれば終了コード 0' do
      code, received = run_framed(request(1, 'initialize', { 'protocolVersion' => '0.1' }), request(2, 'shutdown'),
                                  notification('exit'), request(3, 'profile/list'))
      expect(code).to eq(0)
      expect(received.map { |m| m['id'] }).to eq([1, 2])
    end

    it 'shutdown なしの exit と、exit なしで入力が終わったときは終了コード 1' do
      expect(run_framed(request(1, 'initialize', { 'protocolVersion' => '0.1' }), notification('exit')).first).to eq(1)
      expect(run_framed(request(1, 'initialize', { 'protocolVersion' => '0.1' })).first).to eq(1)
    end
  end

  describe 'メッセージの形' do
    before { initialize! }

    it 'JSON-RPC 2.0 の形でないリクエストは -32600（id が分かればその id で）' do
      expect(server.handle([1, 2])).to include(id: nil, error: include(code: -32_600))
      expect(server.handle({ 'id' => 5, 'method' => 'profile/list' })).to include(id: 5, error: include(code: -32_600))
      expect(server.handle({ 'jsonrpc' => '2.0', 'id' => [1], 'method' => 'x' })).to include(id: nil, error: include(code: -32_600))
      expect(server.handle({ 'jsonrpc' => '2.0', 'method' => 1 })).to be_nil
    end

    it '知らないメソッドは -32601、$/ で始まるものは何もしない' do
      expect(server.handle(request(1, 'nope'))[:error][:code]).to eq(-32_601)
      expect(server.handle(request(2, '$/unknown'))).to eq(jsonrpc: '2.0', id: 2, result: nil)
      expect(server.handle(notification('$/cancelRequest', { 'id' => 1 }))).to be_nil
      expect(server.handle(notification('nope'))).to be_nil
    end

    it '拡張からの応答（method のない id 付きのもの）は読み捨てる' do
      expect(server.handle({ 'jsonrpc' => '2.0', 'id' => 1, 'result' => {} })).to be_nil
    end

    it 'JSON として読めない本文には -32700 を返して続ける' do
      code, received = run_framed(raw: "Content-Length: 5\r\n\r\n{oops")
      expect(code).to eq(1)
      expect(received).to eq([{ 'jsonrpc' => '2.0', 'id' => nil, 'error' => { 'code' => -32_700, 'message' => 'JSON として読めません' } }])
    end

    it '枠が読めなければログに書いて終わる' do
      code, received = run_framed(raw: "Content-Type: x\r\n\r\n{}")
      expect([code, received]).to eq([1, []])
      expect(error.string).to include('[cornix serve]').and include('Content-Length')
    end
  end

  describe 'エラーの code への変換' do
    before do
      initialize!
      Class.new(handler) do
        rpc 'test/fail'
        def call(_params, _context) = raise(Cornix::Interface::EditorServer::RpcError.new(-32_060, '版が違います', { files: {} }))
      end
      Class.new(handler) do
        rpc 'test/missing'
        def call(params, context) = context.workbench.fetch(params['profileId'])
      end
      Class.new(handler) do
        rpc 'test/config'
        def call(_params, _context) = raise(Cornix::ConfigError, '読めません')
      end
      Class.new(handler) do
        rpc 'test/boom'
        def call(_params, _context) = raise('こわれた')
      end
    end

    it 'RpcError はその code・message・data' do
      expect(server.handle(request(1, 'test/fail'))[:error]).to eq(code: -32_060, message: '版が違います', data: { files: {} })
    end

    it 'ProfileNotFound は -32050（data に profileId か dir）' do
      expect(server.handle(request(1, 'test/missing', { 'profileId' => 'p9' }))[:error])
        .to include(code: -32_050, data: { profileId: 'p9' })
    end

    it 'ほかの Cornix::Error は -32603 で message にその文を入れる' do
      expect(server.handle(request(1, 'test/config'))[:error]).to eq(code: -32_603, message: '読めません')
    end

    it '予期しない例外は -32603 にして、ログにバックトレースを書く' do
      expect(server.handle(request(1, 'test/boom'))[:error]).to include(code: -32_603, message: include('こわれた'))
      expect(error.string).to include('test/boom の処理で例外: RuntimeError')
    end

    it '通知の失敗は応答せず、ログに書く' do
      expect(server.handle(notification('test/fail'))).to be_nil
      expect(error.string).to include('通知 test/fail を処理できませんでした')
    end
  end

  it 'ハンドラは context.notify で拡張に通知を送れる' do
    Class.new(handler) do
      rpc 'test/notify'
      def call(params, context)
        context.notify('profile/didChange', { profileId: params['profileId'] })
        { ok: true }
      end
    end
    _, received = run_framed(request(1, 'initialize', { 'protocolVersion' => '0.1' }),
                             request(2, 'test/notify', { 'profileId' => 'p1' }))
    expect(received.drop(1)).to eq([{ 'jsonrpc' => '2.0', 'method' => 'profile/didChange', 'params' => { 'profileId' => 'p1' } },
                                     { 'jsonrpc' => '2.0', 'id' => 2, 'result' => { 'ok' => true } }])
  end

  describe 'profile/close' do
    before { initialize! }

    it '開いたプロファイルを閉じる（知らない id でも何もしない）' do
      FileUtils.mkdir_p(File.join(@root, 'profiles', 'a'))
      id = workbench.open('profiles/a').id
      expect(server.handle(notification('profile/close', { 'profileId' => id }))).to be_nil
      expect { workbench.fetch(id) }.to raise_error(Cornix::Application::Editor::ProfileNotFound)
      expect(server.handle(notification('profile/close', { 'profileId' => 'p9' }))).to be_nil
    end

    it 'profileId がなければ応答せずログに書く' do
      expect(server.handle(notification('profile/close', {}))).to be_nil
      expect(error.string).to include('profileId')
    end
  end
end
