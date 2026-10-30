# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'

RSpec.describe 'features/status のハンドラ' do
  around do |example|
    Dir.mktmpdir('cornix-features') do |dir|
      @home = dir
      example.run
    end
  end

  let(:env) { { 'XDG_CONFIG_HOME' => @home } }

  def request
    server = Cornix::Interface::EditorServer::Server.new(workbench: Object.new, input: StringIO.new, output: StringIO.new,
                                                         error: StringIO.new)
    server.handle({ 'jsonrpc' => '2.0', 'id' => 0, 'method' => 'initialize', 'params' => { 'protocolVersion' => '0.5' } })
    server.handle({ 'jsonrpc' => '2.0', 'id' => 1, 'method' => 'features/status', 'params' => {} })
  end

  it 'ファイルがなければ何も解放しない' do
    expect(Cornix::Storage::FeatureUnlock.unlocked(env: env)).to eq([])
  end

  it 'ファイルがあれば解放する' do
    path = Cornix::Storage::FeatureUnlock.path(env)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, '')
    expect(Cornix::Storage::FeatureUnlock.unlocked(env: env)).to eq(['editor.byKey'])
  end

  it '編集のサーバーだけが受け持ち、一覧を返す' do
    allow(Cornix::Storage::FeatureUnlock).to receive(:unlocked).and_return(['editor.byKey'])
    expect(request[:result]).to eq(unlocked: ['editor.byKey'])
    expect(Cornix::Interface::EditorServer::Handler.fetch('features/status', server: :device)).to be_nil
  end
end
