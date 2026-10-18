# frozen_string_literal: true

require 'spec_helper'
require 'yaml'
require_relative '../support/vil_image'

# 旧 compile が書いた layout.vil を正解として、to_profile → to_image で元のイメージに戻ることを確かめる
RSpec.describe Cornix::Mapping::ProfileMapper, '旧 compile の layout.vil との往復' do
  subject(:mapper) { described_class.new }

  root = File.expand_path('../../..', __dir__)
  cases = {
    'spec/fixtures の設定' => [File.join(root, 'spec/fixtures/layout.vil'),
                               File.join(root, 'spec/fixtures/test_config/position_map.yaml')],
    'authors-keymap の設定' => [File.expand_path('../domain-architecture/tmp/baseline/layout.vil', root),
                                File.expand_path('../../authors-keymap/config/position_map.yaml', root)]
  }

  cases.each do |label, (vil_path, position_map_path)|
    context label do
      before do
        missing = [vil_path, position_map_path].reject { |p| File.exist?(p) }
        skip "#{missing.join(', ')} がありません" unless missing.empty?
      end

      let(:image) { VilImage.load(vil_path) }
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
