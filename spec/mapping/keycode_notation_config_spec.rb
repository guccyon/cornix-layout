# frozen_string_literal: true

require 'spec_helper'
require 'yaml'

# 実際の設定ファイルに書かれたキーコードをすべて解釈でき、旧コードと同じ 16bit 値になること。
# 旧コードの値 = 旧 compile が .vil に書いた文字列（KeycodeValue#to_qmk）を旧 Device::Keycodes#encode した値
# （spec/fixtures/expected/config_keycodes.yaml に保存したもの。旧コードで値にできなかった文字列は null）。
RSpec.describe Cornix::Mapping::KeycodeNotation, '実際の設定ファイル' do
  fixtures = File.expand_path('../fixtures', __dir__)
  configs = {
    'test_config' => File.join(fixtures, 'test_config'),
    'authors_config' => File.join(fixtures, 'authors_config')
  }
  old_codes = YAML.safe_load_file(File.join(fixtures, 'expected', 'config_keycodes.yaml'))

  # 設定ディレクトリからキーコードの文字列を集める
  def self.keycode_strings(dir)
    strings = []
    collect = lambda do |node|
      case node
      when Hash then node.each_value { |v| collect.(v) }
      when Array then node.each { |v| collect.(v) }
      when String then strings << node
      end
    end
    load = ->(sub) { Dir[File.join(dir, sub, '*.{yml,yaml}')].sort.map { |f| YAML.safe_load_file(f) } }
    load.('layers').each { |d| collect.(d['mapping']) }
    load.('tap_dance').each { |d| collect.(d['actions'] || d.slice('on_tap', 'on_hold', 'on_double_tap', 'on_tap_hold')) }
    load.('combos').each { |d| collect.(d.slice('trigger_keys', 'output_key')) }
    load.('macros').each do |d|
      Array(d['sequence']).each { |step| collect.(step['keys']) if %w[tap down up].include?(step['action']) }
    end
    strings.uniq
  end

  def self.references(dir)
    names = lambda do |sub|
      Dir[File.join(dir, sub, '*.{yml,yaml}')].to_h { |f| YAML.safe_load_file(f).values_at('name', 'index') }
    end
    Cornix::Mapping::References.new(macros: names.('macros'), tap_dances: names.('tap_dance'))
  end

  subject(:notation) { described_class.new }

  configs.each do |label, dir|
    context label do
      let(:strings) { self.class.keycode_strings(dir) }
      let(:references) { self.class.references(dir) }

      # 旧 compile が書く文字列の 16bit 値（旧コードで値にできなければ nil）
      define_method(:old_code) { |text| old_codes.fetch(label).fetch(text) }

      it 'キーコードの文字列をすべて解釈できる' do
        expect(strings).not_to be_empty
        expect(strings).to match_array(old_codes.fetch(label).keys)
        failures = strings.filter_map do |text|
          notation.parse(text, references: references)
          nil
        rescue Cornix::UnknownKeycode => e
          e.message
        end
        expect(failures).to be_empty
      end

      it '旧コードが値にできたものは同じ 16bit 値になる' do
        compared = 0
        mismatches = strings.filter_map do |text|
          expected = old_code(text) or next
          compared += 1
          actual = notation.codec.encode(notation.parse(text, references: references))
          "#{text}: 旧 0x#{format('%04X', expected)} / 新 0x#{format('%04X', actual)}" unless actual == expected
        end
        expect(mismatches).to be_empty
        expect(compared).to be > strings.size / 2
      end

      it 'format した文字列を parse すると同じ値に戻る' do
        strings.each do |text|
          keycode = notation.parse(text, references: references)
          expect(notation.parse(notation.format(keycode, references: references), references: references)).to eq(keycode)
        end
      end
    end
  end
end
