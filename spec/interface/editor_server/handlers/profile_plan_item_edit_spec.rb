# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'stringio'
require 'tmpdir'

# profile/planItemEdit のハンドラ。応答の約束は spec/fixtures/protocol/profile_plan_item_edit の適合テスト。
# ここでは params の読み方（edit の形の誤りの field）と、保存の流れ（当てて profile/saved）を確かめる
RSpec.describe Cornix::Interface::EditorServer::Handlers::ProfilePlanItemEdit do
  around do |example|
    Dir.mktmpdir('cornix-item-edit-handler') do |dir|
      @root = File.realpath(dir)
      FileUtils.mkdir_p(File.join(@root, 'profiles'))
      FileUtils.cp_r(File.join(__dir__, '../../../fixtures/test_config'), File.join(@root, 'profiles/default'))
      example.run
    end
  end

  let(:workbench) { Cornix::Application::Editor::Workbench.new(root: @root) }
  let(:server) do
    Cornix::Interface::EditorServer::Server.new(workbench: workbench, input: StringIO.new, output: StringIO.new(+''),
                                                error: StringIO.new).tap do |s|
      s.handle({ 'jsonrpc' => '2.0', 'id' => 0, 'method' => 'initialize', 'params' => { 'protocolVersion' => '0.1' } })
    end
  end

  def path(rel) = File.join(@root, 'profiles/default', rel)
  def request(method, params) = server.handle({ 'jsonrpc' => '2.0', 'id' => 1, 'method' => method, 'params' => params })
  def open = request('profile/open', { 'dir' => 'profiles/default' })[:result]
  def item_edit(edit, base_versions = {}) = request('profile/planItemEdit', { 'profileId' => 'p1', 'baseVersions' => base_versions, 'edit' => edit })

  it 'メソッドが登録されている（リクエスト）' do
    expect(Cornix::Interface::EditorServer::Handler.fetch('profile/planItemEdit')).to eq(described_class)
    expect(described_class.notification?).to be(false)
  end

  it 'edit の形の誤りは -32602 で、data.field にその項目' do
    open
    {
      { 'op' => 'create', 'kind' => 'combo', 'name' => 'X', 'preset' => 'macOS:システム:ウィンドウキャプチャ' } => 'edit.preset',
      { 'op' => 'create', 'kind' => 'shortcut', 'name' => 'X' } => 'edit.value',
      { 'op' => 'rename', 'kind' => 'macro', 'name' => 'Macro 0' } => 'edit.to',
      { 'op' => 'renamePosition', 'hand' => 'center', 'row' => 0, 'col' => 0, 'to' => 'x' } => 'edit.hand',
      { 'op' => 'renamePosition', 'hand' => 'left', 'row' => 0, 'to' => 'x' } => 'edit.col',
      { 'op' => 1 } => 'edit.op',
      { 'kind' => 'macro' } => 'edit.op'
    }.each do |edit, field|
      expect(item_edit(edit)[:error]).to include(code: -32_602, data: { field: field })
    end
    expect(request('profile/planItemEdit', { 'profileId' => 'p1' })[:error]).to include(code: -32_602, data: { field: 'edit' })
    expect(item_edit({ 'op' => 'delete', 'kind' => 'macro', 'name' => 'Macro 0' }, { 'x' => 1 })[:error])
      .to include(code: -32_602, data: { field: 'baseVersions.x' })
  end

  it '局所的に書き換えられない操作は -32061（data に address と reason）' do
    File.write(path('shortcuts.yaml'), "shortcuts: { a: KC_A }\n")
    files = open[:files]
    response = item_edit({ 'op' => 'delete', 'kind' => 'shortcut', 'name' => 'a' }, files)
    expect(response[:error]).to include(code: -32_061, data: { address: { file: 'shortcuts.yaml', path: %w[shortcuts a] },
                                                               reason: 'flowInsert' })
  end

  it '返した書き換えを当てて保存し profile/saved で知らせると、新しい名前で読める' do
    files = open[:files]
    result = item_edit({ 'op' => 'rename', 'kind' => 'macro', 'name' => 'Macro 0', 'to' => 'Brackets' }, files)[:result]
    saved = {}
    result[:files].each do |entry|
      text = File.read(path(entry[:file]))
      edits = entry[:edits].map do |e|
        r = e[:range]
        Cornix::Storage::TextEdit.new(range: Cornix::Storage::TextRange.new(start_line: r[:start][:line], start_character: r[:start][:character],
                                                                            end_line: r[:end][:line], end_character: r[:end][:character]),
                                      new_text: e[:newText])
      end
      target = entry[:renameTo] || entry[:file]
      File.delete(path(entry[:file])) if entry[:renameTo]
      File.write(path(target), Cornix::Storage::TextEdit.apply(text, edits))
      saved[entry[:file]] = nil if entry[:renameTo]
      saved[target] = Cornix::Storage::FileVersion.read(path(target))
    end
    snapshot = request('profile/saved', { 'profileId' => 'p1', 'files' => saved })[:result]
    expect(snapshot[:references][:macros].first).to include(index: 0, name: 'Brackets')
    expect(snapshot[:files]).to include('macros/00_brackets.yaml')
    expect(snapshot[:files]).not_to include('macros/00_macro.yaml')
  end
end
