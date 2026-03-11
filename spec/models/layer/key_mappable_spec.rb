# frozen_string_literal: true

require 'spec_helper'
require_relative '../../../lib/cornix/models/layer/key_mappable'
require_relative '../../../lib/cornix/models/layer/null_key_mapping'
require_relative '../../../lib/cornix/converters/keycode_converter'

RSpec.describe Cornix::Models::Layer::KeyMappable do
  let(:aliases_path) { File.join(__dir__, '../../../lib/cornix/keycode_aliases.yaml') }
  let(:keycode_converter) { Cornix::Converters::KeycodeConverter.new(aliases_path) }

  # テスト用のダミークラス（KeyMappable を include するが、実装しない）
  class IncompleteKeyMapping
    include Cornix::Models::Layer::KeyMappable
  end

  describe 'interface enforcement' do
    it 'raises NotImplementedError for #symbol' do
      incomplete = IncompleteKeyMapping.new
      expect { incomplete.symbol }.to raise_error(NotImplementedError, /must implement #symbol/)
    end

    it 'raises NotImplementedError for #to_qmk' do
      incomplete = IncompleteKeyMapping.new
      expect {
        incomplete.to_qmk(keycode_converter)
      }.to raise_error(NotImplementedError, /must implement #to_qmk/)
    end

    it 'raises NotImplementedError for #to_yaml' do
      incomplete = IncompleteKeyMapping.new
      expect { incomplete.to_yaml }.to raise_error(NotImplementedError, /must implement #to_yaml/)
    end

    it 'raises NotImplementedError for #logical_coord' do
      incomplete = IncompleteKeyMapping.new
      expect { incomplete.logical_coord }.to raise_error(NotImplementedError, /must implement #logical_coord/)
    end
  end
end

RSpec.describe Cornix::Models::Layer::NullKeyMapping do
  let(:aliases_path) { File.join(__dir__, '../../../lib/cornix/keycode_aliases.yaml') }
  let(:keycode_converter) { Cornix::Converters::KeycodeConverter.new(aliases_path) }
  let(:null_key) { described_class.new }

  describe '#symbol' do
    it 'returns nil' do
      expect(null_key.symbol).to be_nil
    end
  end

  describe '#to_qmk' do
    it 'returns -1 (NoKey)' do
      expect(null_key.to_qmk(keycode_converter)).to eq(-1)
    end

    it 'returns -1 even with reference_converter' do
      expect(null_key.to_qmk(keycode_converter, reference_converter: nil)).to eq(-1)
    end
  end

  describe '#to_yaml' do
    it 'returns nil' do
      expect(null_key.to_yaml).to be_nil
    end
  end

  describe '#logical_coord' do
    it 'returns nil' do
      expect(null_key.logical_coord).to be_nil
    end
  end

  describe 'KeyMappable compliance' do
    it 'includes KeyMappable module' do
      expect(described_class.ancestors).to include(Cornix::Models::Layer::KeyMappable)
    end

    it 'responds to all KeyMappable methods' do
      expect(null_key).to respond_to(:symbol)
      expect(null_key).to respond_to(:to_qmk)
      expect(null_key).to respond_to(:to_yaml)
      expect(null_key).to respond_to(:logical_coord)
    end
  end

  describe 'Cornix::Models::Layer::NULL_KEY' do
    it 'is a NullKeyMapping instance' do
      expect(Cornix::Models::Layer::NULL_KEY).to be_a(described_class)
    end

    it 'is frozen (immutable)' do
      expect(Cornix::Models::Layer::NULL_KEY).to be_frozen
    end

    it 'has correct behavior' do
      null = Cornix::Models::Layer::NULL_KEY
      expect(null.symbol).to be_nil
      expect(null.to_qmk(keycode_converter)).to eq(-1)
      expect(null.to_yaml).to be_nil
      expect(null.logical_coord).to be_nil
    end
  end
end
