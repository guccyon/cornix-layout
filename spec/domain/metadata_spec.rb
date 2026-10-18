# frozen_string_literal: true

require 'spec_helper'
require 'yaml'

RSpec.describe Cornix::Domain::Metadata do
  let(:fixture) { YAML.load_file(File.expand_path('../fixtures/test_config/metadata.yaml', __dir__)) }
  let(:authors) do
    {
      'keyboard' => 'cornix', 'version' => 1, 'uid' => 16_882_930_253_541_522_617,
      'vial_protocol' => 6, 'via_protocol' => 9,
      'extra_keys' => { 'layout_options' => 0, 'alt_repeat_key' => [], 'key_override' => [] },
      'file_naming' => { 'layers' => { 'pattern' => '{index}_{name}.yaml', 'index_range' => [0, 9] } },
      'references' => { 'macros' => { 'preferred' => 'MACRO(name)' } }
    }
  end

  describe '.from_h' do
    it '名前の付いた項目を読み、それ以外は extra に元の順で持つ' do
      md = described_class.from_h(authors)
      expect(md.keyboard).to eq('cornix')
      expect(md.version).to eq(1)
      expect(md.uid).to eq(16_882_930_253_541_522_617)
      expect(md.vial_protocol).to eq(6)
      expect(md.via_protocol).to eq(9)
      expect(md.vendor_product_id).to be_nil
      expect(md.extra.keys).to eq(%w[extra_keys file_naming references])
      expect(md.extra_keys).to eq('layout_options' => 0, 'alt_repeat_key' => [], 'key_override' => [])
    end

    it 'to_h で元の内容に戻る（未使用の項目も落とさない）' do
      expect(described_class.from_h(authors).to_h).to eq(authors)
    end

    it 'spec の fixture（nil の項目を含む）を読める。nil の項目は to_h で省く' do
      md = described_class.from_h(fixture)
      expect(md.keyboard).to eq('Cornix')
      expect(md.matrix).to be_nil
      expect(md.to_h).to eq(fixture.compact)
    end

    it 'extra は深く freeze されている' do
      md = described_class.from_h(authors)
      expect(md.extra).to be_frozen
      expect(md.extra['file_naming']['layers']['index_range']).to be_frozen
    end

    it 'Hash でなければ InvalidValue' do
      expect { described_class.from_h(nil) }.to raise_error(Cornix::InvalidValue, /Hash/)
    end
  end

  describe '構造検証' do
    def build(**overrides) = described_class.new(keyboard: 'cornix', version: 1, **overrides)

    it 'keyboard は必須の空でない文字列' do
      expect { described_class.new(keyboard: nil, version: 1) }.to raise_error(Cornix::InvalidValue, /keyboard/)
      expect { described_class.new(keyboard: '', version: 1) }.to raise_error(Cornix::InvalidValue, /keyboard/)
    end

    it 'version は必須の整数' do
      expect { described_class.new(keyboard: 'cornix', version: nil) }.to raise_error(Cornix::InvalidValue, /version/)
      expect { build(version: '1') }.to raise_error(Cornix::InvalidValue, /version/)
    end

    it 'uid / vial_protocol / via_protocol は 0 以上の整数か nil' do
      expect(build(uid: nil).uid).to be_nil
      expect { build(uid: '') }.to raise_error(Cornix::InvalidValue, /uid/)
      expect { build(vial_protocol: '6') }.to raise_error(Cornix::InvalidValue, /vial_protocol/)
      expect { build(via_protocol: -1) }.to raise_error(Cornix::InvalidValue, /via_protocol/)
    end

    it 'vendor_product_id は 0xXXXX' do
      expect(build(vendor_product_id: '0x4C4B').vendor_product_id).to eq('0x4C4B')
      expect { build(vendor_product_id: '4C4B') }.to raise_error(Cornix::InvalidValue, /0xXXXX/)
      expect { build(vendor_product_id: '0x4C4') }.to raise_error(Cornix::InvalidValue)
      expect { build(vendor_product_id: 0x4C4B) }.to raise_error(Cornix::InvalidValue)
    end

    it 'matrix の rows / cols は正の整数' do
      expect(build(matrix: { 'rows' => 8, 'cols' => 7 }).matrix).to eq('rows' => 8, 'cols' => 7)
      expect { build(matrix: { 'rows' => 0, 'cols' => 7 }) }.to raise_error(Cornix::InvalidValue, /matrix.rows/)
      expect { build(matrix: { 'rows' => 8, 'cols' => '7' }) }.to raise_error(Cornix::InvalidValue, /matrix.cols/)
      expect { build(matrix: [8, 7]) }.to raise_error(Cornix::InvalidValue, /matrix/)
    end

    it 'extra は文字列のキーの Hash で、名前の付いた項目を含まない' do
      expect { build(extra: { extra_keys: {} }) }.to raise_error(Cornix::InvalidValue, /文字列/)
      expect { build(extra: { 'uid' => 1 }) }.to raise_error(Cornix::InvalidValue, /uid/)
      expect { build(extra: nil) }.to raise_error(Cornix::InvalidValue)
    end

    it 'extra_keys がなければ空の Hash' do
      expect(build.extra_keys).to eq({})
    end
  end
end
