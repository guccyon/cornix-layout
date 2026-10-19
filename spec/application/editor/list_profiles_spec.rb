# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Cornix::Application::Editor::ListProfiles do
  around do |example|
    Dir.mktmpdir('cornix-list') do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  def mkdir(rel, content: false)
    path = File.join(@root, rel)
    FileUtils.mkdir_p(path)
    File.write(File.join(path, 'metadata.yaml'), "keyboard: cornix\n") if content
  end

  def list = described_class.new(root: @root).call

  it 'profiles/ の下（名前の順）・.cornix.yml の config:・中身のある config/ をこの順に並べる' do
    mkdir('profiles/work')
    mkdir('profiles/alice')
    mkdir('layouts/mine')
    mkdir('config', content: true)
    File.write(File.join(@root, '.cornix.yml'), "config: layouts/mine\n")
    expect(list).to eq(profiles: [{ dir: 'profiles/alice', name: 'alice' }, { dir: 'profiles/work', name: 'work' },
                                  { dir: 'layouts/mine', name: 'mine' }, { dir: 'config', name: 'config' }],
                       default: 'layouts/mine')
  end

  it '--profile に使えない名前・ファイル・中身のない config/ は並べない' do
    mkdir('profiles/.hidden')
    mkdir('profiles/ok')
    File.write(File.join(@root, 'profiles', 'note.txt'), '')
    mkdir('config')
    expect(list).to eq(profiles: [{ dir: 'profiles/ok', name: 'ok' }], default: nil)
  end

  it '.cornix.yml の profile: が既定になり、同じディレクトリは 1 回だけ並べる' do
    mkdir('profiles/ipad')
    File.write(File.join(@root, '.cornix.yml'), "config: profiles/ipad\n")
    expect(list).to eq(profiles: [{ dir: 'profiles/ipad', name: 'ipad' }], default: 'profiles/ipad')
    File.write(File.join(@root, '.cornix.yml'), "profile: ipad\n")
    expect(list[:default]).to eq('profiles/ipad')
  end

  it '.cornix.yml が指す root の外のディレクトリは絶対パス' do
    Dir.mktmpdir('cornix-outside') do |outside|
      outside = File.realpath(outside)
      File.write(File.join(@root, '.cornix.yml'), "config: #{outside}\n")
      expect(list).to eq(profiles: [{ dir: outside, name: File.basename(outside) }], default: outside)
    end
  end

  it '.cornix.yml がないとき既定は中身のある config/、なければ nil' do
    mkdir('profiles/default')
    expect(list[:default]).to be_nil
    mkdir('config', content: true)
    expect(list[:default]).to eq('config')
  end

  it '.cornix.yml が指すディレクトリがない・読めないときは既定を nil にして残りを並べる' do
    mkdir('profiles/default')
    File.write(File.join(@root, '.cornix.yml'), "profile: missing\n")
    expect(list).to eq(profiles: [{ dir: 'profiles/default', name: 'default' }], default: nil)
    File.write(File.join(@root, '.cornix.yml'), "- broken\n")
    expect(list).to eq(profiles: [{ dir: 'profiles/default', name: 'default' }], default: nil)
  end

  it '環境変数 CORNIX_CONFIG は見ない' do
    mkdir('profiles/a')
    mkdir('config', content: true)
    original = ENV.fetch('CORNIX_CONFIG', nil)
    ENV['CORNIX_CONFIG'] = File.join(@root, 'profiles', 'a')
    expect(list[:default]).to eq('config')
  ensure
    original.nil? ? ENV.delete('CORNIX_CONFIG') : ENV['CORNIX_CONFIG'] = original
  end
end
