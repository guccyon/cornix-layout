# frozen_string_literal: true

require 'spec_helper'
require 'json'
require_relative 'support/storage_helpers'
require_relative '../../lib/cornix/device/keycodes'

# authors-keymap の config を読み込んだ Profile が、旧コードで compile した tmp/baseline/layout.vil と
# 16bit 値で一致すること（ProfileMapper の代わりに、位置ごとに codec.encode と旧 Device::Keycodes#encode を比べる）
RSpec.describe 'Storage::ConfigRepository と旧 compile の結果（authors-keymap）' do
  include StorageHelpers

  before do
    skip 'authors-keymap の config がありません' unless File.directory?(StorageHelpers::AUTHORS_CONFIG)
    skip 'tmp/baseline/layout.vil がありません' unless File.file?(StorageHelpers::BASELINE_VIL)
  end

  let(:profile) { repository(StorageHelpers::AUTHORS_CONFIG).load }
  let(:vil) { JSON.parse(File.read(StorageHelpers::BASELINE_VIL)) }
  let(:codec) { Cornix::Mapping::KeycodeCodec.new }
  let(:old) { Cornix::Device::Keycodes.new }

  def code(keycode) = codec.encode(keycode)

  it '問題なく読める（意味検証のエラーもない）' do
    expect(profile.diagnostics.select(&:error?)).to be_empty
  end

  it 'レイヤーのすべての位置が一致する' do
    map = profile.position_map
    mismatches = vil['layout'].each_with_index.flat_map do |rows, index|
      layer = profile.layer(index)
      map.positions.filter_map do |pos|
        row, col = map.matrix(pos)
        cell = rows[row][col]
        expected = cell == -1 ? nil : old.encode(cell)
        actual = layer.key(pos)&.then { |k| code(k) }
        "layer #{index} #{map.path(pos)}: 旧 #{expected.inspect} / 新 #{actual.inspect}" unless actual == expected
      end
    end
    expect(mismatches).to be_empty
    expect(profile.layers.map(&:index).sort).to eq((0...vil['layout'].size).to_a)
  end

  it 'エンコーダ（プッシュ・回転）が一致する' do
    vil['layout'].each_with_index do |rows, index|
      layer = profile.layer(index)
      %i[left right].each_with_index do |side, i|
        row, col = profile.position_map.encoder_push_matrix(side)
        binding = layer.encoder(side)
        expect(code(binding.push)).to eq(old.encode(rows[row][col]))
        expect([code(binding.ccw), code(binding.cw)]).to eq(vil['encoder_layout'][index][i].map { |c| old.encode(c) })
      end
    end
  end

  it 'マクロが一致する' do
    expected = vil['macro'].each_with_index.reject { |steps, _| steps.empty? }.to_h do |steps, index|
      [index, steps.map { |kind, *rest| [kind, *(%w[tap down up].include?(kind) ? rest.map { |k| old.encode(k) } : rest)] }]
    end
    actual = profile.macros.to_h do |macro|
      [macro.index, macro.steps.map do |step|
        case step
        when Cornix::Domain::MacroStep::Delay then ['delay', step.ms]
        when Cornix::Domain::MacroStep::Text then ['text', step.content]
        else [step.kind.to_s, *step.keys.map { |k| code(k) }]
        end
      end]
    end
    expect(actual).to eq(expected)
  end

  it 'タップダンスが一致する' do
    profile.tap_dances.each do |td|
      expected = vil['tap_dance'][td.index]
      actual = td.actions.values.map { |k| code(k) } + [td.tapping_term]
      expect(actual).to eq(expected[0, 4].map { |c| old.encode(c) } + [expected[4]])
    end
    unused = vil['tap_dance'].each_index.to_a - profile.tap_dances.map(&:index)
    expect(unused.map { |i| vil['tap_dance'][i] }).to all(eq(['KC_NO', 'KC_NO', 'KC_NO', 'KC_NO', 250]))
  end

  it 'コンボが一致する' do
    profile.combos.each do |combo|
      expected = vil['combo'][combo.index].map { |c| old.encode(c) }
      triggers = combo.trigger_keys.map { |k| code(k) }
      expect(triggers + ([0] * (4 - triggers.size)) + [code(combo.output_key)]).to eq(expected)
    end
    unused = vil['combo'].each_index.to_a - profile.combos.map(&:index)
    expect(unused.map { |i| vil['combo'][i] }).to all(eq(['KC_NO'] * 5))
  end

  it 'QMK の設定とメタデータが一致する' do
    expect(profile.settings.values).to eq(vil['settings'].to_h { |k, v| [Integer(k, 10), v] })
    metadata = profile.metadata
    expect([metadata.version, metadata.uid, metadata.vial_protocol, metadata.via_protocol])
      .to eq(vil.values_at('version', 'uid', 'vial_protocol', 'via_protocol'))
    expect(metadata.extra_keys).to eq(vil.slice('layout_options', 'alt_repeat_key', 'key_override'))
  end

  it '旧 decompile の出力（tmp/baseline/decompiled_config）も読めて、キーコードが同じになる' do
    old_dir = File.join(File.dirname(StorageHelpers::BASELINE_VIL), 'decompiled_config')
    skip 'decompiled_config がありません' unless File.directory?(old_dir)

    decompiled = repository(old_dir).load
    expect(decompiled.layers.map { |l| [l.keys, l.encoders] }).to eq(profile.layers.map { |l| [l.keys, l.encoders] })
    expect(decompiled.macros.map(&:steps)).to eq(profile.macros.map(&:steps))
    expect(decompiled.tap_dances.map(&:actions)).to eq(profile.tap_dances.map(&:actions))
    expect(decompiled.combos.map(&:output_key)).to eq(profile.combos.map(&:output_key))
    expect(decompiled.settings).to eq(profile.settings)
  end

  it 'save して読み直すと同じ Profile になる' do
    Dir.mktmpdir do |tmp|
      repo = repository(tmp)
      repo.save(profile)
      expect(repo.load).to eq(profile)
    end
  end
end
