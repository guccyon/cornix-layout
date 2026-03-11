# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../lib/cornix/models/settings'

RSpec.describe Cornix::Models::Settings do
  let(:sample_settings_hash) do
    {
      'tapping_term' => 200,
      'combo_term' => 50,
      'leader_timeout' => 300
    }
  end

  describe '.from_qmk' do
    it 'QMK HashからSettingsを生成' do
      settings = described_class.from_qmk(sample_settings_hash)

      expect(settings.settings_hash).to eq(sample_settings_hash)
    end

    it 'nil を許容（空のHash）' do
      settings = described_class.from_qmk(nil)

      expect(settings.settings_hash).to eq({})
    end
  end

  describe '#to_qmk' do
    it 'SettingsをQMK Hashに変換' do
      settings = described_class.from_qmk(sample_settings_hash)
      qmk_hash = settings.to_qmk

      expect(qmk_hash).to eq(sample_settings_hash)
    end

    it '空のHashを返す（nilの場合）' do
      settings = described_class.new(nil)
      qmk_hash = settings.to_qmk

      expect(qmk_hash).to eq({})
    end
  end

  describe '.from_yaml_hash' do
    it 'YAML HashからSettingsを生成' do
      settings = described_class.from_yaml_hash(sample_settings_hash)

      expect(settings.settings_hash).to eq(sample_settings_hash)
    end
  end

  describe '#to_yaml_hash' do
    it 'SettingsをYAML Hashに変換' do
      settings = described_class.from_yaml_hash(sample_settings_hash)
      yaml_hash = settings.to_yaml_hash

      expect(yaml_hash).to eq(sample_settings_hash)
    end
  end

  describe 'round-trip conversion' do
    it 'QMK → Settings → QMK の往復変換' do
      settings = described_class.from_qmk(sample_settings_hash)
      qmk_hash = settings.to_qmk

      expect(qmk_hash).to eq(sample_settings_hash)
    end

    it 'YAML → Settings → YAML の往復変換' do
      settings = described_class.from_yaml_hash(sample_settings_hash)
      yaml_hash = settings.to_yaml_hash

      expect(yaml_hash).to eq(sample_settings_hash)
    end
  end

  describe 'edge cases' do
    it '空のHashを許容' do
      settings = described_class.new({})

      expect(settings.settings_hash).to eq({})
      expect(settings.to_qmk).to eq({})
    end

    it 'ネストしたHashを透過的に保持' do
      nested_hash = {
        'parent' => {
          'child' => 'value'
        }
      }
      settings = described_class.new(nested_hash)

      expect(settings.to_qmk).to eq(nested_hash)
    end

    it '配列値を透過的に保持' do
      array_hash = {
        'list' => [1, 2, 3]
      }
      settings = described_class.new(array_hash)

      expect(settings.to_qmk).to eq(array_hash)
    end
  end
end
