# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Cornix::Mapping::QmkSettingCatalog do
  def catalog_from(text)
    Dir.mktmpdir do |dir|
      path = File.join(dir, 'qmk_settings.yaml')
      File.write(path, text)
      return described_class.load(path)
    end
  end

  describe '同梱の data/qmk_settings.yaml' do
    subject(:catalog) { described_class.default }

    it 'QSID・名前・グループ・幅・型を読む' do
      expect(catalog.qsids).to eq([2, 6, 7, 18, 19, 22, 23, 26, 27])
      expect(catalog.find('keyboard', 'permissive_hold').qsid).to eq(22)
      expect(catalog.find('keyboard', 'hold_on_other_key_press').qsid).to eq(23)
      expect(catalog.find('keyboard', 'chordal_hold').qsid).to eq(26)
      expect(catalog.fetch(2)).to have_attributes(name: 'combo_timing_window', group: 'vial', width: 2, type: 'integer')
    end

    it 'すべての設定に日本語の説明がある' do
      catalog.all.each do |definition|
        expect(definition.description).to be_a(String).and(match(/\p{Hiragana}/)), definition.name
      end
    end

    it '既定値は vial-qmk の qmk_settings_reset の値で、型と幅に合う' do
      defaults = catalog.all.to_h { |d| [d.name, d.default] }
      expect(defaults).to eq('combo_timing_window' => 50, 'oneshot_timeout' => 5000, 'tapping_term' => 200,
                             'tap_code_delay' => 10, 'tap_hold_caps_delay' => 80, 'permissive_hold' => false,
                             'hold_on_other_key_press' => false, 'chordal_hold' => false, 'flow_tap' => 0)
      catalog.all.each do |definition|
        if definition.boolean?
          expect(definition.default).to be(true).or(be(false)), definition.name
        else
          expect(definition.default).to be_between(0, definition.max), definition.name
        end
      end
    end
  end

  describe '.load' do
    it 'description と default は省略でき、なければ nil' do
      catalog = catalog_from("settings:\n  - { qsid: 7, name: tapping_term, group: keyboard, width: 2, type: integer }\n")
      expect(catalog.fetch(7)).to have_attributes(description: nil, default: nil, max: 0xFFFF)
    end

    it '知らない項目や足りない項目は ConfigError' do
      expect { catalog_from("settings:\n  - { qsid: 7, name: a, group: keyboard, width: 2, type: integer, foo: 1 }\n") }
        .to raise_error(Cornix::ConfigError)
      expect { catalog_from("settings:\n  - { qsid: 7, name: a, group: keyboard, width: 2 }\n") }
        .to raise_error(Cornix::ConfigError)
    end

    it 'QSID が重複していれば ConfigError' do
      text = "settings:\n  - { qsid: 7, name: a, group: keyboard, width: 2, type: integer }\n" \
             "  - { qsid: 7, name: b, group: keyboard, width: 2, type: integer }\n"
      expect { catalog_from(text) }.to raise_error(Cornix::ConfigError, /QSID が重複/)
    end
  end

  describe Cornix::Mapping::QmkSettingCatalog::Definition do
    it '位置引数でも作れて、boolean? と max を返す' do
      definition = described_class.new(22, 'permissive_hold', 'keyboard', 1, 'boolean', nil, nil)
      expect(definition).to have_attributes(boolean?: true, max: 1, description: nil, default: nil)
      expect(described_class.new(qsid: 7, name: 'tapping_term', group: 'keyboard', width: 2, type: 'integer').max)
        .to eq(0xFFFF)
    end
  end
end
