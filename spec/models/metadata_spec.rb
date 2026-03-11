# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../lib/cornix/models/metadata'

RSpec.describe Cornix::Models::Metadata do
  let(:sample_qmk_hash) do
    {
      'version' => 5,
      'uid' => 'ABC123',
      'vendor_product_id' => '0x1234',
      'product_id' => '0x5678',
      'matrix' => { 'rows' => 8, 'cols' => 7 },
      'vial_protocol' => 6,
      'via_protocol' => 12
    }
  end

  let(:sample_yaml_hash) do
    {
      'keyboard' => 'Cornix',
      'version' => 5,
      'uid' => 'ABC123',
      'vendor_product_id' => '0x1234',
      'product_id' => '0x5678',
      'matrix' => { 'rows' => 8, 'cols' => 7 },
      'vial_protocol' => 6,
      'via_protocol' => 12
    }
  end

  describe '.from_qmk' do
    it 'QMK HashからMetadataを生成' do
      metadata = described_class.from_qmk(sample_qmk_hash)

      expect(metadata.keyboard).to eq('Cornix')
      expect(metadata.version).to eq(5)
      expect(metadata.uid).to eq('ABC123')
      expect(metadata.vendor_product_id).to eq('0x1234')
      expect(metadata.product_id).to eq('0x5678')
      expect(metadata.matrix).to eq({ 'rows' => 8, 'cols' => 7 })
      expect(metadata.vial_protocol).to eq(6)
      expect(metadata.via_protocol).to eq(12)
    end
  end

  describe '#to_qmk' do
    it 'MetadataをQMK Hashに変換' do
      metadata = described_class.from_qmk(sample_qmk_hash)
      qmk_hash = metadata.to_qmk

      expect(qmk_hash['version']).to eq(5)
      expect(qmk_hash['uid']).to eq('ABC123')
      expect(qmk_hash['vendor_product_id']).to eq('0x1234')
      expect(qmk_hash['product_id']).to eq('0x5678')
      expect(qmk_hash['matrix']).to eq({ 'rows' => 8, 'cols' => 7 })
      expect(qmk_hash['vial_protocol']).to eq(6)
      expect(qmk_hash['via_protocol']).to eq(12)
    end

    it 'keyboard フィールドは含まれない（QMK形式）' do
      metadata = described_class.from_qmk(sample_qmk_hash)
      qmk_hash = metadata.to_qmk

      expect(qmk_hash).not_to have_key('keyboard')
    end
  end

  describe '.from_yaml_hash' do
    it 'YAML HashからMetadataを生成' do
      metadata = described_class.from_yaml_hash(sample_yaml_hash)

      expect(metadata.keyboard).to eq('Cornix')
      expect(metadata.version).to eq(5)
      expect(metadata.uid).to eq('ABC123')
    end
  end

  describe '#to_yaml_hash' do
    it 'MetadataをYAML Hashに変換' do
      metadata = described_class.from_yaml_hash(sample_yaml_hash)
      yaml_hash = metadata.to_yaml_hash

      expect(yaml_hash['keyboard']).to eq('Cornix')
      expect(yaml_hash['version']).to eq(5)
      expect(yaml_hash['uid']).to eq('ABC123')
      expect(yaml_hash['vendor_product_id']).to eq('0x1234')
      expect(yaml_hash['matrix']).to eq({ 'rows' => 8, 'cols' => 7 })
    end
  end

  describe 'round-trip conversion' do
    it 'QMK → Metadata → QMK の往復変換' do
      metadata = described_class.from_qmk(sample_qmk_hash)
      qmk_hash = metadata.to_qmk

      expect(qmk_hash['version']).to eq(sample_qmk_hash['version'])
      expect(qmk_hash['uid']).to eq(sample_qmk_hash['uid'])
      expect(qmk_hash['matrix']).to eq(sample_qmk_hash['matrix'])
    end

    it 'YAML → Metadata → YAML の往復変換' do
      metadata = described_class.from_yaml_hash(sample_yaml_hash)
      yaml_hash = metadata.to_yaml_hash

      expect(yaml_hash).to eq(sample_yaml_hash)
    end
  end

  describe 'edge cases' do
    it 'nilフィールドを許容' do
      qmk_hash = sample_qmk_hash.merge('uid' => nil)
      metadata = described_class.from_qmk(qmk_hash)

      expect(metadata.uid).to be_nil
      expect(metadata.to_qmk['uid']).to be_nil
    end

    it '空文字列を許容' do
      qmk_hash = sample_qmk_hash.merge('uid' => '')
      metadata = described_class.from_qmk(qmk_hash)

      expect(metadata.uid).to eq('')
    end

    it 'matrix が Hash であることを保持' do
      metadata = described_class.from_qmk(sample_qmk_hash)

      expect(metadata.matrix).to be_a(Hash)
      expect(metadata.matrix['rows']).to eq(8)
      expect(metadata.matrix['cols']).to eq(7)
    end
  end

  describe 'validation' do
    describe '#structurally_valid?' do
      it 'returns true for valid metadata' do
        metadata = described_class.from_yaml_hash(sample_yaml_hash)
        expect(metadata.structurally_valid?).to be true
      end

      it 'returns false when keyboard is blank' do
        hash = sample_yaml_hash.merge('keyboard' => '')
        metadata = described_class.from_yaml_hash(hash)
        expect(metadata.structurally_valid?).to be false
      end

      it 'returns false when version is not an integer' do
        hash = sample_yaml_hash.merge('version' => 'not an integer')
        metadata = described_class.from_yaml_hash(hash)
        expect(metadata.structurally_valid?).to be false
      end

      it 'validates vendor_product_id format' do
        # 有効なフォーマット
        hash = sample_yaml_hash.merge('vendor_product_id' => '0x1234')
        metadata = described_class.from_yaml_hash(hash)
        expect(metadata.structurally_valid?).to be true

        # 無効なフォーマット
        hash = sample_yaml_hash.merge('vendor_product_id' => '1234')
        metadata = described_class.from_yaml_hash(hash)
        expect(metadata.structurally_valid?).to be false

        # nilは許可
        hash = sample_yaml_hash.merge('vendor_product_id' => nil)
        metadata = described_class.from_yaml_hash(hash)
        expect(metadata.structurally_valid?).to be true
      end

      it 'validates matrix structure' do
        # 有効なmatrix
        hash = sample_yaml_hash.merge('matrix' => { 'rows' => 8, 'cols' => 7 })
        metadata = described_class.from_yaml_hash(hash)
        expect(metadata.structurally_valid?).to be true

        # matrix.rows が非整数
        hash = sample_yaml_hash.merge('matrix' => { 'rows' => 'invalid', 'cols' => 7 })
        metadata = described_class.from_yaml_hash(hash)
        expect(metadata.structurally_valid?).to be false

        # matrix.rows がゼロ以下
        hash = sample_yaml_hash.merge('matrix' => { 'rows' => 0, 'cols' => 7 })
        metadata = described_class.from_yaml_hash(hash)
        expect(metadata.structurally_valid?).to be false

        # matrix がハッシュでない
        hash = sample_yaml_hash.merge('matrix' => 'not a hash')
        metadata = described_class.from_yaml_hash(hash)
        expect(metadata.structurally_valid?).to be false

        # matrix が nil
        hash = sample_yaml_hash.merge('matrix' => nil)
        metadata = described_class.from_yaml_hash(hash)
        expect(metadata.structurally_valid?).to be true
      end
    end

    describe '#structural_errors' do
      it 'returns empty array for valid metadata' do
        metadata = described_class.from_yaml_hash(sample_yaml_hash)
        expect(metadata.structural_errors).to be_empty
      end

      it 'includes error for blank keyboard' do
        hash = sample_yaml_hash.merge('keyboard' => '')
        metadata = described_class.from_yaml_hash(hash)
        errors = metadata.structural_errors
        expect(errors.size).to be > 0
        expect(errors.join(' ')).to include('cannot be blank')
      end

      it 'includes error for non-integer version' do
        hash = sample_yaml_hash.merge('version' => 'invalid')
        metadata = described_class.from_yaml_hash(hash)
        errors = metadata.structural_errors
        expect(errors.size).to be > 0
        expect(errors.join(' ')).to include('must be an integer')
      end

      it 'includes error for invalid vendor_product_id format' do
        hash = sample_yaml_hash.merge('vendor_product_id' => 'invalid')
        metadata = described_class.from_yaml_hash(hash)
        errors = metadata.structural_errors
        expect(errors.size).to be > 0
        expect(errors.join(' ')).to include('format invalid')
      end

      it 'includes error for invalid matrix' do
        hash = sample_yaml_hash.merge('matrix' => { 'rows' => 'invalid', 'cols' => 7 })
        metadata = described_class.from_yaml_hash(hash)
        errors = metadata.structural_errors
        expect(errors.size).to be > 0
        expect(errors.join(' ')).to include('matrix')
      end
    end

    describe '#validate!' do
      it 'does not raise for valid metadata' do
        metadata = described_class.from_yaml_hash(sample_yaml_hash)
        expect { metadata.validate! }.not_to raise_error
      end

      it 'raises ValidationError for invalid metadata' do
        hash = sample_yaml_hash.merge('keyboard' => '', 'version' => 'invalid')
        metadata = described_class.from_yaml_hash(hash)
        expect { metadata.validate! }.to raise_error(Cornix::Models::Concerns::ValidationError)
      end
    end

    describe '.from_yaml_hash with validation errors' do
      it 'raises ArgumentError when keyboard is missing' do
        hash = sample_yaml_hash.merge('keyboard' => nil)
        expect {
          described_class.from_yaml_hash(hash)
        }.to raise_error(ArgumentError, /keyboard/)
      end
    end
  end
end
