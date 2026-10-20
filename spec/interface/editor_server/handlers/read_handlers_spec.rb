# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'

# profile/open・keycode/* のハンドラ（中身の約束は spec/fixtures/protocol の適合テスト）
RSpec.describe 'profile/open・keycode/* のハンドラ' do
  around do |example|
    Dir.mktmpdir('cornix-handlers') do |dir|
      @root = File.realpath(dir)
      FileUtils.cp_r(File.join(__dir__, '../../../fixtures/test_config'), File.join(@root, 'profile'))
      example.run
    end
  end

  def server(workbench)
    Cornix::Interface::EditorServer::Server.new(workbench: workbench, input: StringIO.new, output: StringIO.new,
                                                error: StringIO.new).tap do |s|
      s.handle({ 'jsonrpc' => '2.0', 'id' => 0, 'method' => 'initialize', 'params' => { 'protocolVersion' => '0.2' } })
    end
  end

  def request(server, method, params) = server.handle({ 'jsonrpc' => '2.0', 'id' => 1, 'method' => method, 'params' => params })

  it 'メソッドが登録されている' do
    expect(Cornix::Interface::EditorServer::Handler.registry.keys)
      .to include('profile/open', 'keycode/candidates', 'keycode/shortcutTree', 'keycode/inspect')
  end

  it 'profile/open は snapshot を作れなければ開いたものを閉じてからエラーにする' do
    broken = Object.new
    def broken.config_dir = raise(Cornix::Error, '読めません')
    workbench = Cornix::Application::Editor::Workbench.new(root: @root, env_factory: ->(_) { broken })
    response = request(server(workbench), 'profile/open', { 'dir' => 'profile' })
    expect(response[:error]).to include(code: -32_603, message: '読めません')
    expect(workbench.opened).to be_empty
  end

  it 'profile/open の結果の profileId でほかのリクエストができる' do
    workbench = Cornix::Application::Editor::Workbench.new(root: @root)
    s = server(workbench)
    id = request(s, 'profile/open', { 'dir' => 'profile' })[:result][:profileId]
    result = request(s, 'keycode/inspect', { 'profileId' => id, 'context' => 'encoder', 'text' => 'Mute' })[:result]
    expect(result[:value]).to include(canonical: 'Mute', kind: 'basic')
    limit = request(s, 'keycode/candidates', { 'profileId' => id, 'context' => 'layerKey', 'query' => 'a', 'limit' => '3' })
    expect(limit[:error]).to include(code: -32_602, data: { field: 'limit' })
  end
end
