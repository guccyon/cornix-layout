# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'

# 応答と通知の約束は spec/fixtures/protocol/profile_saved（適合テスト）
RSpec.describe Cornix::Application::Editor::Saved do
  around do |example|
    Dir.mktmpdir('cornix-saved') do |dir|
      @root = File.realpath(dir)
      FileUtils.cp_r(File.join(__dir__, '../../fixtures/test_config'), File.join(@root, 'profile'))
      example.run
    end
  end

  let(:workbench) { Cornix::Application::Editor::Workbench.new(root: @root) }
  let(:opened) { workbench.open('profile').tap { |o| Cornix::Application::Editor::Snapshot.new(workbench).call(o.id) } }
  let(:layer) { 'layers/0_layer_0.yaml' }

  def path(rel) = File.join(@root, 'profile', rel)
  def version(rel) = Cornix::Storage::FileVersion.read(path(rel))

  def save(rel, text)
    File.write(path(rel), text)
    version(rel)
  end

  it '保存したファイルを読み直し、知っている版にして snapshot を返す' do
    id = opened.id
    saved = save(layer, File.read(path(layer)).sub('tab: Tab', 'tab: Escape'))
    result = described_class.new(workbench).call(id, files: { layer => saved })
    expect(result.changed?).to be(false)
    expect(result.snapshot[:files][layer]).to eq(saved)
    expect(result.snapshot[:layers][0][:keys][0][:value][:text]).to eq('Escape')
    expect(workbench.versions(id)[layer]).to eq(saved)
  end

  it '保存の直後にさらに外で変わっていれば、読み直した版を changed にする' do
    id = opened.id
    saved = save(layer, File.read(path(layer)).sub('tab: Tab', 'tab: Escape'))
    later = save(layer, File.read(path(layer)).sub('tab: Escape', 'tab: Enter'))
    result = described_class.new(workbench).call(id, files: { layer => saved })
    expect(result.changed).to eq(layer => later)
    expect(result.notification).to include(profileId: id, files: { layer => later }, snapshot: result.snapshot)
    expect(workbench.versions(id)[layer]).to eq(later)
  end

  it '知らされていないファイルが外で変わっていれば、それも changed に入れる（消えたファイルは nil）' do
    id = opened.id
    File.delete(path('combos/03_combo.yaml'))
    result = described_class.new(workbench).call(id, files: {})
    expect(result.changed).to eq('combos/03_combo.yaml' => nil)
  end

  it 'QMK 設定のファイルを作ったときは、知らされた版で照らす' do
    FileUtils.rm(path('settings/qmk_settings.yaml'))
    id = opened.id
    created = save('settings/qmk_settings.yaml', "keyboard:\n  tapping_term: 200\n")
    result = described_class.new(workbench).call(id, files: { 'settings/qmk_settings.yaml' => created })
    expect(result.changed?).to be(false)
    expect(result.snapshot[:files]['settings/qmk_settings.yaml']).to eq(created)
  end

  it '設定ファイルでないファイルは見ない' do
    result = described_class.new(workbench).call(opened.id, files: { 'README.md' => 'sha256:00' })
    expect(result.changed?).to be(false)
  end
end
