# frozen_string_literal: true

require 'spec_helper'
require 'yaml'
require_relative '../support/vil_image'

# 旧 compile が書いた layout.vil（旧コードで求めた 16bit 値）を正解として、to_profile → to_image で元のイメージに戻ることを確かめる
RSpec.describe Cornix::Mapping::ProfileMapper, '旧 compile の layout.vil との往復' do
  subject(:mapper) { described_class.new }

  fixtures = File.expand_path('../../fixtures', __dir__)
  cases = {
    'spec/fixtures の設定' => ['layout', File.join(fixtures, 'test_config/position_map.yaml')],
    'authors-keymap の設定' => ['authors_baseline', File.join(fixtures, 'authors_config/position_map.yaml')]
  }

  cases.each do |label, (vil_name, position_map_path)|
    context label do
      let(:image) { VilImage.load(vil_name) }
      let(:position_map) { Cornix::Domain::PositionMap.from_h(YAML.load_file(position_map_path)) }
      let(:profile) { mapper.to_profile(image, position_map: position_map) }
      let(:result) { mapper.to_image(profile) }

      it '全項目が元のイメージに戻る' do
        Cornix::Image::DeviceImage.members.each do |field|
          expect(result.public_send(field)).to eq(image.public_send(field)), "#{field} が違います"
        end
        expect(result).to eq(image)
      end

      it 'meta の項目の順も保つ' do
        expect(result.meta.keys).to eq(image.meta.keys)
      end

      it 'Profile に意味検証のエラーがない' do
        expect(profile.diagnostics.select(&:error?)).to eq([])
      end

      it '解釈できない値はない（Raw にならない）' do
        raws = profile.layers.flat_map { |l| l.keys.values }.grep(Cornix::Domain::Keycode::Raw)
        expect(raws).to eq([])
      end
    end
  end
end
