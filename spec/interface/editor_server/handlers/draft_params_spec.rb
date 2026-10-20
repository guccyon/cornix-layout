# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'stringio'
require 'tmpdir'

# profile/validate・profile/planEdits の Change の読み方（protocol.md の 12.3 の op・field・index・from・to）。
# params の形の誤りは版の食い違い（-32060）より先に -32602 になる
RSpec.describe 'profile/validate・planEdits の Change の params' do
  around do |example|
    Dir.mktmpdir('cornix-draft-params') do |dir|
      @root = File.realpath(dir)
      FileUtils.mkdir_p(File.join(@root, 'profiles'))
      FileUtils.cp_r(File.join(__dir__, '../../../fixtures/test_config'), File.join(@root, 'profiles/default'))
      example.run
    end
  end

  let(:server) do
    workbench = Cornix::Application::Editor::Workbench.new(root: @root)
    Cornix::Interface::EditorServer::Server.new(workbench: workbench, input: StringIO.new, output: StringIO.new(+''),
                                                error: StringIO.new).tap do |s|
      s.handle({ 'jsonrpc' => '2.0', 'id' => 0, 'method' => 'initialize', 'params' => { 'protocolVersion' => '0.1' } })
      s.handle({ 'jsonrpc' => '2.0', 'id' => 0, 'method' => 'profile/open', 'params' => { 'dir' => 'profiles/default' } })
    end
  end
  let(:combo) { 'combos/00_combo.yaml' }

  def version(rel) = Cornix::Storage::FileVersion.read(File.join(@root, 'profiles/default', rel))

  def plan(change, base_versions: { combo => version(combo) })
    params = { 'profileId' => 'p1', 'baseVersions' => base_versions,
               'changes' => [{ 'address' => { 'file' => combo, 'path' => ['trigger_keys'] } }.merge(change)] }
    server.handle({ 'jsonrpc' => '2.0', 'id' => 1, 'method' => 'profile/planEdits', 'params' => params })
  end

  def error_field(change, **options)
    error = plan(change, **options).fetch(:error)
    expect(error[:code]).to eq(-32_602)
    error[:data][:field]
  end

  it 'op ごとに要る項目がなく、形が違えば -32602（版の食い違いより先）' do
    stale = { base_versions: { combo => 'sha256:00' } }
    expect(error_field({ 'op' => 'rename' }, **stale)).to eq('changes[0].op')
    expect(error_field({ 'op' => 1 }, **stale)).to eq('changes[0].op')
    expect(error_field({ 'op' => 'insert', 'value' => 'KC_A' }, **stale)).to eq('changes[0].index')
    expect(error_field({ 'op' => 'insert', 'index' => 0, 'value' => 1 }, **stale)).to eq('changes[0].value')
    expect(error_field({ 'op' => 'move', 'from' => 0 }, **stale)).to eq('changes[0].to')
    expect(error_field({ 'op' => 'move', 'from' => 0.5, 'to' => 1 }, **stale)).to eq('changes[0].from')
    expect(error_field({ 'op' => 'set', 'value' => { 'action' => 'tap' } }, **stale)).to eq('changes[0].value')
    expect(error_field({ 'op' => 'insert', 'index' => 0, 'value' => 'KC_A', 'field' => 'note' }, **stale)).to eq('changes[0].field')
    expect(error_field({ 'value' => 'KC_A', 'field' => 'title' }, **stale)).to eq('changes[0].field')
    expect(plan({ 'op' => 'remove' }, **stale).dig(:error, :code)).to eq(-32_060)
  end

  it 'remove は value がいらず、insert と move は位置で指す' do
    result = plan({ 'op' => 'insert', 'index' => 4, 'value' => 'KC_G' }).fetch(:result)
    expect(result[:files].first[:edits].map { |e| e[:newText] }).to eq(["\n- KC_G"])
    result = plan({ 'op' => 'move', 'from' => 0, 'to' => 1 }).fetch(:result)
    expect(result[:files].size).to eq(1)
    response = server.handle({ 'jsonrpc' => '2.0', 'id' => 2, 'method' => 'profile/validate',
                               'params' => { 'profileId' => 'p1', 'baseVersions' => { combo => version(combo) },
                                             'changes' => [{ 'op' => 'remove', 'address' => { 'file' => combo, 'path' => ['description'] } }] } })
    expect(response.fetch(:result)).to eq(diagnostics: [])
  end
end
