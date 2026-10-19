# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'

# 応答の形の約束は spec/fixtures/protocol/profile_validate（適合テスト）
RSpec.describe Cornix::Application::Editor::ValidateDraft do
  around do |example|
    Dir.mktmpdir('cornix-validate-draft') do |dir|
      @root = File.realpath(dir)
      FileUtils.cp_r(File.join(__dir__, '../../fixtures/test_config'), File.join(@root, 'profile'))
      example.run
    end
  end

  let(:workbench) { Cornix::Application::Editor::Workbench.new(root: @root) }
  let(:opened) { workbench.open('profile') }
  let(:layer) { 'layers/0_layer_0.yaml' }

  def version(rel) = Cornix::Storage::FileVersion.read(File.join(@root, 'profile', rel))

  def validate(changes)
    base = changes.map(&:file).uniq.to_h { |f| [f, version(f)] }
    described_class.new(workbench).call(opened.id, base_versions: base, changes: changes)
  end

  def change(path, value) = Cornix::Application::Editor::PlanEdits::Change.new(file: layer, path: path, value: value)

  it '変更がなければ保存済みの中身の検証の結果（cornix validate と同じ）' do
    expect(validate([])).to eq(diagnostics: [])
  end

  it 'ファイルも知っている版も変えない' do
    Cornix::Application::Editor::Snapshot.new(workbench).call(opened.id)
    known = workbench.versions(opened.id).dup
    before = File.read(File.join(@root, 'profile', layer))
    validate([change(%w[mapping left_hand row0 tab], 'Macro(20)')])
    expect(File.read(File.join(@root, 'profile', layer))).to eq(before)
    expect(workbench.versions(opened.id)).to eq(known)
  end

  it '意味検証の warning（Cornix が対応していないキー）も返す' do
    result = validate([change(%w[mapping left_hand row0 tab], 'Repeat')])
    expect(result[:diagnostics]).to contain_exactly(include(severity: 'warning', source: 'semantic',
                                                            address: { file: layer, path: %w[mapping left_hand row0 tab] }))
  end

  it '変更で直った問題は出さない' do
    File.write(File.join(@root, 'profile', layer),
               File.read(File.join(@root, 'profile', layer)).sub('tab: Tab', 'tab: Macro(20)'))
    expect(validate([])[:diagnostics].size).to eq(1)
    expect(validate([change(%w[mapping left_hand row0 tab], 'Tab')])).to eq(diagnostics: [])
  end
end
