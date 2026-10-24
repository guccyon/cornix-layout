# frozen_string_literal: true

require 'spec_helper'
require_relative 'support/storage_helpers'

RSpec.describe 'Storage::ConfigRepository#load_partial（エディタ用。読めない値は NoKey にして読み続ける）' do
  include StorageHelpers

  let(:dir) { StorageHelpers::AUTHORS_CONFIG }
  let(:disk) { Cornix::Storage::FileSource::Disk.new(dir) }
  let(:base) { disk.read('layers/0_base.yml') }

  def repository_with(files)
    Cornix::Storage::ConfigRepository.new(dir, notation: notation, settings_catalog: settings_catalog,
                                               source: Cornix::Storage::FileSource::Overlay.new(disk, files))
  end

  it '問題がなければ load と同じ Profile で、問題は空' do
    partial = repository_with({}).load_partial
    expect(partial.profile).to eq(repository_with({}).load)
    expect(partial.problems).to eq([])
  end

  it '解析できないキーコードは問題にしたうえで NoKey にして読む（load は今までどおり InvalidConfig）' do
    repo = repository_with('layers/0_base.yml' => base.sub('      Q: Q', '      Q: KC_FOOO'))
    partial = repo.load_partial
    position = partial.profile.position_map.position('left_hand', 'row0', 'Q')
    expect(partial.profile.layer(0).key(position)).to eq(Cornix::Domain::Keycode::NO_KEY)
    expect(partial.problems.map(&:to_s)).to eq(['layers/0_base.yml: mapping.left_hand.row0.Q: キーコード「KC_FOOO」を解釈できません: 「KC_FOOO」は不明なキーコードです'])
    expect { repo.load }.to raise_error(Cornix::Storage::InvalidConfig)
  end

  it 'ほかの問題（型の誤りなど）があれば、読めない値の問題も一緒に InvalidConfig' do
    repo = repository_with('layers/0_base.yml' => base.sub('      Q: Q', '      Q: KC_FOOO').sub('      W: W', '      W: [W]'))
    expect { repo.load_partial }.to raise_error(Cornix::Storage::InvalidConfig) { |e|
      expect(e.problems.map(&:location)).to contain_exactly('mapping.left_hand.row0.Q', 'mapping.left_hand.row0.W')
    }
  end
end
