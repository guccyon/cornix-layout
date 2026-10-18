# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require_relative '../../application/device_environment_context'

RSpec.describe Cornix::Interface::Cli::Main do
  let(:out) { StringIO.new }
  let(:err) { StringIO.new }
  let(:input) { StringIO.new }

  def run(*argv, **opts)
    described_class.new(out: out, err: err, input: input, **opts).run(argv)
  end

  it 'コマンドの表は名前 → Command のクラス' do
    expect(described_class::COMMANDS.keys).to eq(%w[device mcp])
    expect(described_class::COMMANDS.values).to all(be < Cornix::Interface::Cli::Command)
  end

  it '引数がなければ、または help で一覧を表示する' do
    expect(run).to eq(0)
    expect(out.string).to include('device').and include('mcp').and include('help')
    expect(run('help', 'device')).to eq(0)
    expect(out.string).to include('cornix device read [-o FILE]')
  end

  it '知らないコマンドは exit 1' do
    expect(run('nope')).to eq(1)
    expect(err.string).to include('エラー: 知らないコマンドです: nope')
  end

  it 'コマンドを足せる（commands と use_cases を差し替える）' do
    hello = Class.new(Cornix::Interface::Cli::Command) do
      command 'hello', 'あいさつ'
      def run(args)
        _, opts = parse!(args) { |p, o| p.on('--name NAME') { |n| o[:name] = n } }
        out.line(use_case(:device_info).call.to_h[:greeting] + opts[:name])
        Cornix::Interface::Cli::Command::SUCCESS
      end
    end
    stub = ->(_env) { Struct.new(:call).new(Cornix::Application::InfoResult.new(info: { greeting: 'こんにちは ' })) }
    status = run('hello', '--name', 'Cornix', commands: described_class::COMMANDS.merge('hello' => hello),
                                              use_cases: { device_info: stub }, env_factory: -> { :env })
    expect(status).to eq(0)
    expect(out.string).to eq("こんにちは Cornix\n")
  end

  it 'Cornix::Error は「エラー: …」で exit 1' do
    failing = ->(_env) { Struct.new(:call).new.tap { |o| def o.call = raise(Cornix::DeviceError, 'Cornix が見つかりません') } }
    expect(run('device', 'info', use_cases: { device_info: failing }, env_factory: -> { :env })).to eq(1)
    expect(err.string).to eq("エラー: Cornix が見つかりません\n")
  end

  it 'mcp は MCP サーバーを起動する' do
    server = double('server', run: nil)
    expect(run('mcp', env_factory: -> { :env }, mcp_factory: ->(env) { env == :env && server })).to eq(0)
    expect(server).to have_received(:run)
  end

  it 'オプションの誤りは使い方の案内つきで exit 1' do
    expect(run('device', 'info', '--bogus', env_factory: -> { :env })).to eq(1)
    expect(err.string).to include('エラー: invalid option: --bogus').and include('cornix help')
  end
end
