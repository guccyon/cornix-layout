# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'stringio'
require 'tmpdir'

# profile/validate・profile/planEdits・profile/saved・workspace/didChangeFiles のハンドラ。
# 中身の約束は spec/fixtures/protocol の適合テスト。ここでは、適合テストのデータでは書けない「途中でファイルが変わる」流れを確かめる
RSpec.describe 'profile/validate・planEdits・saved・workspace/didChangeFiles のハンドラ' do
  around do |example|
    Dir.mktmpdir('cornix-write-handlers') do |dir|
      @root = File.realpath(dir)
      FileUtils.mkdir_p(File.join(@root, 'profiles'))
      FileUtils.cp_r(File.join(__dir__, '../../../fixtures/test_config'), File.join(@root, 'profiles/default'))
      example.run
    end
  end

  let(:output) { StringIO.new(+'') }
  let(:workbench) { Cornix::Application::Editor::Workbench.new(root: @root) }
  let(:server) do
    Cornix::Interface::EditorServer::Server.new(workbench: workbench, input: StringIO.new, output: output,
                                                error: StringIO.new).tap do |s|
      s.handle({ 'jsonrpc' => '2.0', 'id' => 0, 'method' => 'initialize', 'params' => { 'protocolVersion' => '0.3' } })
    end
  end
  let(:layer) { 'layers/0_layer_0.yaml' }

  def path(rel) = File.join(@root, 'profiles/default', rel)
  def version(rel) = Cornix::Storage::FileVersion.read(path(rel))
  def request(method, params) = server.handle({ 'jsonrpc' => '2.0', 'id' => 1, 'method' => method, 'params' => params })
  def notify(method, params) = server.handle({ 'jsonrpc' => '2.0', 'method' => method, 'params' => params })

  # サーバーが出力に書いた通知
  def notifications
    output.rewind
    list = []
    while (m = Cornix::Interface::EditorServer::Framing.read(output))
      list << m
    end
    list.select { |m| m.key?('method') }
  end

  def open = request('profile/open', { 'dir' => 'profiles/default' })[:result]

  it 'メソッドが登録されている（workspace/didChangeFiles は通知）' do
    registry = Cornix::Interface::EditorServer::Handler.registry
    expect(registry.keys).to include('profile/validate', 'profile/planEdits', 'profile/saved', 'workspace/didChangeFiles')
    expect(registry.fetch('workspace/didChangeFiles').notification?).to be(true)
  end

  it '外でファイルが変わったら profile/didChange を送る。同じ知らせをもう一度受けても送らない' do
    snapshot = open
    File.write(path(layer), File.read(path(layer)).sub('tab: Tab', 'tab: Escape'))
    params = { 'changes' => [{ 'path' => "profiles/default/#{layer}", 'type' => 'changed' }] }
    expect(notify('workspace/didChangeFiles', params)).to be_nil
    notify('workspace/didChangeFiles', params)
    sent = notifications
    expect(sent.size).to eq(1)
    expect(sent.first['method']).to eq('profile/didChange')
    expect(sent.first['params']).to include('profileId' => snapshot[:profileId], 'files' => { layer => version(layer) })
    expect(sent.first['params']['snapshot']).to include('profileId' => snapshot[:profileId], 'status' => 'ok')
  end

  it '外の変更で構造検証が通らなくなれば status: invalid の snapshot を送り、直れば描き直せる snapshot を送る' do
    open
    original = File.read(path(layer))
    params = { 'changes' => [{ 'path' => "profiles/default/#{layer}", 'type' => 'changed' }] }
    File.write(path(layer), original.sub('tab: Tab', "tab: Macro('Removed')"))
    notify('workspace/didChangeFiles', params)
    File.write(path(layer), original)
    notify('workspace/didChangeFiles', params)
    expect(notifications.map { |n| n['params']['snapshot']['status'] }).to eq(%w[invalid ok])
  end

  it '書き換えを当てて保存し、profile/saved で読み直すと、以降の baseVersions はその snapshot の版になる' do
    snapshot = open
    change = { 'address' => { 'file' => layer, 'path' => %w[mapping left_hand row0 tab] }, 'value' => 'Escape' }
    plan = request('profile/planEdits', { 'profileId' => snapshot[:profileId],
                                          'baseVersions' => { layer => snapshot[:files][layer] }, 'changes' => [change] })[:result]
    edit = plan[:files].first[:edits].first
    lines = File.read(path(layer)).lines
    line = lines[edit[:range][:start][:line]]
    line[edit[:range][:start][:character]...edit[:range][:end][:character]] = edit[:newText]
    File.write(path(layer), lines.join)

    saved = request('profile/saved', { 'profileId' => snapshot[:profileId], 'files' => { layer => version(layer) } })[:result]
    expect(saved[:files][layer]).to eq(version(layer))
    expect(notifications).to be_empty
    stale = request('profile/validate', { 'profileId' => snapshot[:profileId],
                                          'baseVersions' => { layer => snapshot[:files][layer] }, 'changes' => [change] })
    expect(stale[:error]).to include(code: -32_060, data: { files: { layer => version(layer) } })
    fresh = request('profile/validate', { 'profileId' => snapshot[:profileId],
                                          'baseVersions' => { layer => saved[:files][layer] }, 'changes' => [change] })
    expect(fresh[:result]).to eq(diagnostics: [])
  end

  it 'profile/saved のあとに、溜めておいた保存したファイルの workspace/didChangeFiles を受けても送らない（6.2 の 5）' do
    snapshot = open
    File.write(path(layer), File.read(path(layer)).sub('tab: Tab', 'tab: Escape'))
    request('profile/saved', { 'profileId' => snapshot[:profileId], 'files' => { layer => version(layer) } })
    notify('workspace/didChangeFiles', { 'changes' => [{ 'path' => "profiles/default/#{layer}", 'type' => 'changed' }] })
    expect(notifications).to be_empty
  end

  it 'params の形の誤りは版の食い違いより先に -32602、形が正しければ版の食い違いが宛先や値の型より先' do
    snapshot = open
    stale = snapshot[:files][layer]
    File.write(path(layer), File.read(path(layer)).sub('tab: Tab', 'tab: Escape'))
    address = { 'file' => layer, 'path' => %w[mapping left_hand row0 tab] }
    params = ->(value) { { 'profileId' => snapshot[:profileId], 'baseVersions' => { layer => stale }, 'changes' => [{ 'address' => address, 'value' => value }] } }
    expect(request('profile/planEdits', params.(1.5))[:error]).to include(code: -32_602, data: { field: 'changes[0].value' })
    expect(request('profile/planEdits', params.(nil))[:error]).to include(code: -32_602, data: { field: 'changes[0].value' })
    expect(request('profile/planEdits', params.(1))[:error]).to include(code: -32_060)
  end

  it 'baseVersions の値が文字列でも null でもなければ -32602' do
    snapshot = open
    response = request('profile/validate', { 'profileId' => snapshot[:profileId], 'baseVersions' => { layer => 1 } })
    expect(response[:error]).to include(code: -32_602, data: { field: "baseVersions.#{layer}" })
  end
end
