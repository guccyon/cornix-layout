# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../lib/cornix/models/settings'

RSpec.describe Cornix::Models::Settings do
  # QMK整数インデックス形式（layout.vilから読み込んだ形式）
  let(:qmk_index_hash) do
    { 7 => 250, 22 => 1, 23 => 0, 2 => 50 }
  end

  # YAML可読形式（config/settings/qmk_settings.yamlに書く形式）
  let(:yaml_readable_hash) do
    {
      'keyboard' => {
        'tapping_term'   => 250,
        'chordal_hold'   => true,
        'permissive_hold' => false
      },
      'vial' => {
        'combo_timing_window' => 50
      }
    }
  end

  describe '.from_qmk' do
    it 'QMK整数インデックス形式からSettingsを生成' do
      settings = described_class.from_qmk(qmk_index_hash)
      expect(settings.settings_hash).to eq(qmk_index_hash)
    end

    it 'nil を許容（空のHash）' do
      settings = described_class.from_qmk(nil)
      expect(settings.settings_hash).to eq({})
    end
  end

  describe '#to_qmk' do
    context 'from_qmk経由（整数インデックス形式）' do
      it '整数インデックス形式をそのまま返す' do
        settings = described_class.from_qmk(qmk_index_hash)
        expect(settings.to_qmk).to eq(qmk_index_hash)
      end

      it '空のHashを返す（nilの場合）' do
        settings = described_class.new(nil)
        expect(settings.to_qmk).to eq({})
      end
    end

    context 'from_yaml_hash経由（YAML可読形式）' do
      it 'keyboard/vialネスト形式をVial整数インデックス形式に変換する' do
        settings = described_class.from_yaml_hash(yaml_readable_hash)
        result = settings.to_qmk

        expect(result[7]).to eq(250)    # tapping_term
        expect(result[22]).to eq(1)     # chordal_hold: true → 1
        expect(result[23]).to eq(0)     # permissive_hold: false → 0
        expect(result[2]).to eq(50)     # combo_timing_window
      end

      it 'booleanをtrue→1, false→0に変換する' do
        settings = described_class.from_yaml_hash({
          'keyboard' => { 'chordal_hold' => true, 'permissive_hold' => false }
        })
        result = settings.to_qmk

        expect(result[22]).to eq(1)
        expect(result[23]).to eq(0)
      end

      it '指定されていない設定はresultに含まない' do
        settings = described_class.from_yaml_hash({
          'keyboard' => { 'tapping_term' => 200 }
        })
        result = settings.to_qmk

        expect(result.keys).to eq([7])
      end

      it 'keyboard/vialネストなしの空Hashは空のQMK Hashを返す' do
        settings = described_class.from_yaml_hash({})
        expect(settings.to_qmk).to eq({})
      end

      it 'keyboardのみ定義した場合' do
        settings = described_class.from_yaml_hash({
          'keyboard' => { 'tapping_term' => 300, 'flow_tap' => 100 }
        })
        result = settings.to_qmk

        expect(result[7]).to eq(300)   # tapping_term
        expect(result[27]).to eq(100)  # flow_tap
        expect(result.key?(2)).to be false  # combo_timing_windowは含まない
      end
    end
  end

  describe '.from_yaml_hash' do
    it 'YAML HashからSettingsを生成し、settings_hashを保持する' do
      settings = described_class.from_yaml_hash(yaml_readable_hash)
      expect(settings.settings_hash).to eq(yaml_readable_hash)
    end
  end

  describe '#to_yaml_hash' do
    it 'YAML形式の設定をそのまま返す（人間可読形式を保持）' do
      settings = described_class.from_yaml_hash(yaml_readable_hash)
      expect(settings.to_yaml_hash).to eq(yaml_readable_hash)
    end
  end

  describe 'round-trip' do
    it 'YAML → Settings → YAML の往復変換（可読形式を保持）' do
      settings = described_class.from_yaml_hash(yaml_readable_hash)
      expect(settings.to_yaml_hash).to eq(yaml_readable_hash)
    end

    it 'QMK → Settings → QMK の往復変換（整数インデックスを保持）' do
      settings = described_class.from_qmk(qmk_index_hash)
      expect(settings.to_qmk).to eq(qmk_index_hash)
    end
  end

  describe 'edge cases' do
    it '空のHashを許容' do
      settings = described_class.new({})

      expect(settings.settings_hash).to eq({})
      expect(settings.to_qmk).to eq({})
    end

    it 'keyboard/vialキーがないHashは整数インデックス形式としてパススルーする' do
      flat_hash = { 7 => 250, 18 => 20 }
      settings = described_class.new(flat_hash)

      expect(settings.to_qmk).to eq(flat_hash)
    end
  end
end
