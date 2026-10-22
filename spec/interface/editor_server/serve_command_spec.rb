# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'tmpdir'

RSpec.describe Cornix::Interface::Cli::Commands::Serve do
  def framing = Cornix::Interface::EditorServer::Framing

  def framed(*messages)
    io = StringIO.new(+'')
    messages.each { |m| framing.write(io, m) }
    io.rewind
    io
  end

  def run(*argv, input:, out:, err: StringIO.new)
    Cornix::Interface::Cli::Main.new(out: out, err: err, input: input).run(argv)
  end

  it 'cornix serve --root DIR は標準入出力で JSON-RPC を話し、shutdown → exit で 0 を返す' do
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p(File.join(root, 'profiles', 'default'))
      input = framed({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '0.4' } },
                     { jsonrpc: '2.0', id: 2, method: 'profile/list', params: {} },
                     { jsonrpc: '2.0', id: 3, method: 'shutdown' }, { jsonrpc: '2.0', method: 'exit' })
      out = StringIO.new(+'')
      expect(run('serve', '--root', root, input: input, out: out)).to eq(0)
      out.rewind
      responses = Array.new(3) { framing.read(out) }
      expect(responses[0]['result']['serverInfo']).to eq('name' => 'cornix', 'version' => Cornix::VERSION, 'implementation' => 'ruby')
      expect(responses[1]['result']).to eq('profiles' => [{ 'dir' => 'profiles/default', 'name' => 'default' }],
                                           'default' => nil)
      expect(responses[2]).to eq('jsonrpc' => '2.0', 'id' => 3, 'result' => nil)
      expect(framing.read(out)).to be_nil # 標準出力には応答のほか何も書かない
    end
  end

  it '--root のディレクトリがなければエラー（標準出力には何も書かない）' do
    out = StringIO.new
    err = StringIO.new
    expect(run('serve', '--root', '/nonexistent/cornix', input: StringIO.new, out: out, err: err)).to eq(1)
    expect(out.string).to be_empty
    expect(err.string).to include('--root のディレクトリがありません')
  end

  it '--config / --profile は使えない（UsageError）' do
    %w[--config --profile].each do |flag|
      err = StringIO.new
      expect(run('serve', flag, 'x', input: StringIO.new, out: StringIO.new, err: err)).to eq(1)
      expect(err.string).to include('serve では --config / --profile は使えません')
    end
  end

  it 'cornix serve --device は device のサーバー（device/* だけ。--allow-writes で deviceWrites: true）' do
    Dir.mktmpdir do |root|
      [[[], false], [['--allow-writes'], true]].each do |flags, writes|
        input = framed({ jsonrpc: '2.0', id: 1, method: 'initialize', params: { protocolVersion: '0.4' } },
                       { jsonrpc: '2.0', id: 2, method: 'profile/list', params: {} },
                       { jsonrpc: '2.0', id: 3, method: 'device/backups', params: { dir: 'nope' } },
                       { jsonrpc: '2.0', id: 4, method: 'shutdown' }, { jsonrpc: '2.0', method: 'exit' })
        out = StringIO.new(+'')
        expect(run('serve', '--device', *flags, '--root', root, input: input, out: out)).to eq(0)
        out.rewind
        responses = Array.new(4) { framing.read(out) }
        expect(responses[0]['result']['capabilities']).to include('device' => true, 'deviceWrites' => writes)
        expect(responses[1]['error']['code']).to eq(-32_601)
        expect(responses[2]['error']).to include('code' => -32_050, 'data' => { 'dir' => 'nope' })
      end
    end
  end

  it '--allow-writes は --device と一緒に使う（UsageError）' do
    err = StringIO.new
    expect(run('serve', '--allow-writes', input: StringIO.new, out: StringIO.new, err: err)).to eq(1)
    expect(err.string).to include('--allow-writes は --device と一緒に使います')
  end

  it 'help に載る' do
    out = StringIO.new
    run('help', input: StringIO.new, out: out)
    expect(out.string).to include('serve')
  end
end
