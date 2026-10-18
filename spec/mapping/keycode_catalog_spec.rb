# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Cornix::Mapping::KeycodeCatalog do
  subject(:catalog) { described_class.default }

  it 'Vial 名・QMK 名・別名から値を引ける' do
    expect(catalog.lookup('KC_ENTER')).to eq(0x28)
    expect(catalog.lookup('KC_ENT')).to eq(0x28)
    expect(catalog.lookup('Enter')).to eq(0x28)
    expect(catalog.lookup('KC_EXLM')).to eq(0x021E)
    expect(catalog.lookup('!')).to eq(0x021E)
    expect(catalog.lookup('¥')).to eq(0x041C)
    expect(catalog.lookup('enter')).to be_nil
  end

  it '.vil の名前と正規の別名を引ける' do
    expect(catalog.vial_name(0x2A)).to eq('KC_BSPACE')
    expect(catalog.vial_name(0x021E)).to be_nil
    expect(catalog.preferred_alias(0x29)).to eq('Escape')
    expect(catalog.preferred_alias(0x021E)).to eq('!')
  end

  it 'Vial GUI に名前のない値（vial: false）は name だけを持ち、Vial 名を持たない' do
    expect(catalog.lookup('QK_LOCK')).to eq(0x7C59)
    expect(catalog.name(0x7C59)).to eq('QK_LOCK')
    expect(catalog.vial_name(0x7C59)).to be_nil
    expect(catalog.name(0x2A)).to eq('KC_BSPACE')
    expect(catalog.quantum?(0x7C59)).to be true
  end

  it '書き込み禁止の値を判定する' do
    expect(catalog.dangerous?(0x7C00)).to be true
    expect(catalog.dangerous?(0x7C03)).to be true
    expect(catalog.dangerous?(0x7C02)).to be false
    expect(catalog.dangerous?(0x7E00)).to be false
  end

  it 'customKeycodes を USER00 からの名前として足せる' do
    custom = described_class.load(custom_keycodes: [{ 'name' => 'BT0' }, { 'name' => 'BT1' }])
    expect(custom.lookup('BT1')).to eq(0x7E01)
  end

  describe '表の不整合' do
    def load_with(aliases)
      Dir.mktmpdir do |dir|
        %w[keycodes.yaml dangerous_keycodes.yaml].each { |f| FileUtils.cp(File.join(Cornix::DATA_DIR, f), dir) }
        File.write(File.join(dir, 'aliases.yaml'), aliases)
        Cornix::Mapping::KeycodeCatalog::Loader.new(data_dir: dir).load
      end
    end

    it '同じ別名が 2 つのキーにあればエラー' do
      expect { load_with("basic:\n  KC_A: [A]\n  KC_B: [A]\n") }.to raise_error(Cornix::ConfigError, /A が重複/)
    end

    it '同じキーが 2 回定義されていればエラー' do
      expect { load_with("basic:\n  KC_A: [A]\n  KC_A: [Aa]\n") }.to raise_error(Cornix::ConfigError)
    end

    it '表にないキーはエラー' do
      expect { load_with("basic:\n  KC_NOPE: [Nope]\n") }.to raise_error(Cornix::ConfigError, /KC_NOPE/)
    end
  end
end
