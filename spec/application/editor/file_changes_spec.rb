# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'

RSpec.describe Cornix::Application::Editor::FileChanges do
  around do |example|
    Dir.mktmpdir('cornix-file-changes') do |dir|
      @root = File.realpath(dir)
      %w[profiles/default profiles/ipad].each do |rel|
        FileUtils.mkdir_p(File.dirname(File.join(@root, rel)))
        FileUtils.cp_r(File.join(__dir__, '../../fixtures/test_config'), File.join(@root, rel))
      end
      example.run
    end
  end

  let(:workbench) { Cornix::Application::Editor::Workbench.new(root: @root) }
  let(:layer) { 'layers/0_layer_0.yaml' }

  def open(dir) = workbench.open(dir).tap { |o| Cornix::Application::Editor::Snapshot.new(workbench).call(o.id) }
  def path(dir, rel) = File.join(@root, dir, rel)
  def version(dir, rel) = Cornix::Storage::FileVersion.read(path(dir, rel))
  def changes(*paths) = described_class.new(workbench).call(paths)

  def edit(dir, rel)
    File.write(path(dir, rel), File.read(path(dir, rel)).sub('tab: Tab', 'tab: Escape'))
  end

  it '中身が知っている版と違えば、変わったファイルと新しい版、snapshot を返し、知っている版を更新する' do
    opened = open('profiles/default')
    edit('profiles/default', layer)
    result = changes("profiles/default/#{layer}")
    expect(result).to contain_exactly(include(profileId: opened.id, files: { layer => version('profiles/default', layer) }))
    expect(result.first[:snapshot][:layers][0][:keys][0][:value][:text]).to eq('Escape')
    expect(workbench.versions(opened.id)[layer]).to eq(version('profiles/default', layer))
    expect(changes("profiles/default/#{layer}")).to eq([])
  end

  it '中身が知っている版と同じなら何も返さない（書いて元に戻したときも）' do
    open('profiles/default')
    File.write(path('profiles/default', layer), File.read(path('profiles/default', layer)))
    expect(changes("profiles/default/#{layer}")).to eq([])
  end

  it 'ファイルが足されたとき・消えたとき（消えたファイルは nil）' do
    open('profiles/default')
    FileUtils.cp(path('profiles/default', 'combos/03_combo.yaml'), path('profiles/default', 'combos/04_combo.yaml'))
    File.delete(path('profiles/default', 'combos/00_combo.yaml'))
    result = changes('profiles/default/combos/04_combo.yaml', 'profiles/default/combos/00_combo.yaml')
    expect(result.first[:files]).to eq('combos/04_combo.yaml' => version('profiles/default', 'combos/04_combo.yaml'),
                                       'combos/00_combo.yaml' => nil)
  end

  it 'ディレクトリごと消えたときも、その中のファイルを nil にする' do
    open('profiles/default')
    FileUtils.rm_rf(path('profiles/default', 'combos'))
    result = changes('profiles/default/combos')
    expect(result.first[:files].keys).to all(start_with('combos/'))
    expect(result.first[:files].values).to all(be_nil)
  end

  it '設定ディレクトリの親を指す知らせも見る（profiles/ ごと消えた・名前が変わった）。消えたら files はすべて nil で status: invalid' do
    opened = open('profiles/default')
    FileUtils.mv(File.join(@root, 'profiles'), File.join(@root, 'renamed'))
    result = changes('profiles')
    expect(result.map { |n| n[:profileId] }).to eq([opened.id])
    expect(result.first[:files]).not_to be_empty
    expect(result.first[:files].values).to all(be_nil)
    expect(result.first[:snapshot]).to include(status: 'invalid', diagnostics: [include(source: 'structure')])
    expect(changes('profiles/')).to eq([])
  end

  it '開いているプロファイルの設定ディレクトリの外のパスは見ない（ほかのプロファイルが変わっていても）' do
    open('profiles/default')
    edit('profiles/ipad', layer)
    expect(changes("profiles/ipad/#{layer}", 'notes.txt')).to eq([])
  end

  it '知らせのパスに入っていない設定ファイルの違いも入れる' do
    open('profiles/default')
    edit('profiles/default', layer)
    File.delete(path('profiles/default', 'combos/00_combo.yaml'))
    expect(changes("profiles/default/#{layer}").first[:files].keys).to contain_exactly(layer, 'combos/00_combo.yaml')
  end

  it '絶対パスも受け付け、同じディレクトリを開いたプロファイルそれぞれについて返す' do
    first = open('profiles/default')
    second = open('profiles/default')
    edit('profiles/default', layer)
    expect(changes(path('profiles/default', layer)).map { |n| n[:profileId] }).to eq([first.id, second.id])
  end

  it 'diff は版の違うファイルだけ（ないファイルは nil と同じ）' do
    expect(described_class.diff({ 'a' => 'x', 'b' => nil, 'c' => 'z' }, { 'a' => 'x', 'c' => 'w', 'd' => 'v' }))
      .to eq('c' => 'w', 'd' => 'v')
  end
end
