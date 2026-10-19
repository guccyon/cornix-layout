# frozen_string_literal: true

require 'spec_helper'
require_relative 'support/storage_helpers'

RSpec.describe 'Storage::ConfigRepository の source（保存前の中身で読む）' do
  include StorageHelpers

  let(:dir) { StorageHelpers::AUTHORS_CONFIG }
  let(:disk) { Cornix::Storage::FileSource::Disk.new(dir) }

  def repository_with(files)
    Cornix::Storage::ConfigRepository.new(dir, notation: notation, settings_catalog: settings_catalog,
                                               source: Cornix::Storage::FileSource::Overlay.new(disk, files))
  end

  def problems(repo)
    repo.load
    []
  rescue Cornix::Storage::InvalidConfig => e
    e.problems.map(&:to_s)
  end

  it '既定はディスクの dir を読む（今までどおり）' do
    repo = repository(dir)
    expect(repo.source).to be_a(Cornix::Storage::FileSource::Disk)
    expect(repo.source.dir).to eq(dir)
    expect(repo.load).to eq(repository_with({}).load)
  end

  it '差し替えた中身で読み、ディスクは変えない' do
    text = disk.read('layers/0_base.yml')
    repo = repository_with('layers/0_base.yml' => text.sub('      Q: Q', '      Q: Escape'))
    profile = repo.load
    position = profile.position_map.position('left_hand', 'row0', 'Q')
    expect(profile.layer(0).key(position)).to eq(notation.parse('Escape'))
    expect(disk.read('layers/0_base.yml')).to eq(text)
  end

  it '構造の問題は保存前の中身の位置で報告する' do
    text = disk.read('layers/0_base.yml')
    repo = repository_with('layers/0_base.yml' => text.sub('      Q: Q', "      Q: Macro('Removed')"))
    expect(problems(repo).join).to include('layers/0_base.yml: mapping.left_hand.row0.Q')
  end

  it 'nil にしたファイルはないものとして、足したファイルはあるものとして読む' do
    repo = repository_with('settings/qmk_settings.yaml' => nil)
    expect(repo.load.settings).to be_empty
    expect(problems(repository_with('metadata.yaml' => nil))).to eq(['metadata.yaml: ファイルがありません'])

    layer = disk.read('layers/9_empty.yml').sub('index: 9', 'index: 3')
    expect(problems(repository_with('layers/9_x.yml' => layer)).join).to include('layers/9_x.yml: index')
  end

  it '意味検証の位置と Address も保存前の中身で決める' do
    text = disk.read('layers/0_base.yml')
    repo = repository_with('layers/0_base.yml' => text.sub('      Q: Q', '      Q: { key: M30, note: x }'))
    diagnostic = repo.load.diagnostics.find { |d| d.message.include?('M30') }
    expect(repo.locate(diagnostic).path).to eq('layers/0_base.yml: mapping.left_hand.row0.Q.key')
    expect(repo.address(diagnostic.path)).to eq(['layers/0_base.yml', %w[mapping left_hand row0 Q]])
  end
end
