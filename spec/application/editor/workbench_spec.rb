# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Cornix::Application::Editor::Workbench do
  around do |example|
    Dir.mktmpdir('cornix-workbench') do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  let(:workbench) { described_class.new(root: @root) }

  def mkdir(rel) = FileUtils.mkdir_p(File.join(@root, rel))

  it 'open は id（p1, p2 ...）・dir・name・Environment を返す' do
    mkdir('profiles/default')
    mkdir('config')
    first = workbench.open('profiles/default')
    expect(first).to have_attributes(id: 'p1', dir: 'profiles/default', name: 'default')
    expect(first.env).to be_a(Cornix::Application::Environment)
    expect(first.env.config_dir).to eq(File.join(@root, 'profiles', 'default'))
    expect(first.env.tmp_dir).to eq(File.join(@root, 'tmp', 'profiles', 'default'))
    expect(workbench.open('config')).to have_attributes(id: 'p2', dir: 'config', name: 'config')
  end

  it '同じ dir を開き直すと別の id になる' do
    mkdir('profiles/default')
    expect([workbench.open('profiles/default').id, workbench.open('profiles/default').id]).to eq(%w[p1 p2])
  end

  it 'dir は root からの相対パスにそろえ、root の外は絶対パスのまま' do
    mkdir('profiles/default')
    expect(workbench.open(File.join(@root, 'profiles', 'default')).dir).to eq('profiles/default')
    expect(workbench.open('profiles/./default/').dir).to eq('profiles/default')
    Dir.mktmpdir('cornix-outside') do |outside|
      outside = File.realpath(outside)
      expect(workbench.open(outside)).to have_attributes(dir: outside, name: File.basename(outside))
    end
  end

  it 'env_factory で Environment の作り方を差し替えられる（Workspace が渡る）' do
    mkdir('profiles/ipad')
    seen = nil
    opened = described_class.new(root: @root, env_factory: ->(ws) { seen = ws; :env }).open('profiles/ipad')
    expect(opened.env).to eq(:env)
    expect(seen).to have_attributes(root: @root, config_dir: File.join(@root, 'profiles', 'ipad'), profile_name: 'ipad')
  end

  it 'ないディレクトリ・ファイル・空の dir は ProfileNotFound（dir を持つ）' do
    File.write(File.join(@root, 'file'), '')
    %w[profiles/none file].push('').each do |dir|
      expect { workbench.open(dir) }.to raise_error(Cornix::Application::Editor::ProfileNotFound) { |e| expect(e.dir).to eq(dir) }
    end
  end

  it 'fetch / versions / close' do
    mkdir('profiles/default')
    opened = workbench.open('profiles/default')
    expect(workbench.fetch('p1')).to eq(opened)
    expect(workbench.versions('p1')).to eq({})
    workbench.versions('p1')['layers/0_base.yml'] = 'sha256:00'
    expect(workbench.versions('p1')).to eq('layers/0_base.yml' => 'sha256:00')
    expect(workbench.opened).to eq([opened])
    expect(workbench.close('p1')).to be_nil
    expect(workbench.close('p1')).to be_nil
    expect(workbench.opened).to be_empty
    %i[fetch versions].each do |name|
      expect { workbench.public_send(name, 'p1') }
        .to raise_error(Cornix::Application::Editor::ProfileNotFound, /p1/) { |e| expect(e.profile_id).to eq('p1') }
    end
  end

  it 'root は展開した絶対パス' do
    expect(described_class.new(root: "#{@root}/x/..").root).to eq(@root)
  end
end
