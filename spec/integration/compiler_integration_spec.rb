# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../lib/cornix/compiler'
require_relative '../../lib/cornix/position_map'
require_relative '../../lib/cornix/converters/keycode_converter'
require 'fileutils'
require 'tempfile'
require 'json'

RSpec.describe 'Compiler Integration' do
  let(:temp_dir) { Dir.mktmpdir }
  let(:config_dir) { File.join(temp_dir, 'config') }
  let(:output_path) { File.join(temp_dir, 'layout.vil') }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  def create_minimal_config
    FileUtils.mkdir_p("#{config_dir}/settings")
    FileUtils.mkdir_p("#{config_dir}/layers")
    FileUtils.mkdir_p("#{config_dir}/macros")
    FileUtils.mkdir_p("#{config_dir}/tap_dance")
    FileUtils.mkdir_p("#{config_dir}/combos")

    # metadata.yaml
    File.write("#{config_dir}/metadata.yaml", YAML.dump({
      'keyboard' => 'test_keyboard',
      'version' => 1,
      'uid' => 'TEST123',
      'vendor_product_id' => '0x1234:0x5678',
      'product_id' => '0x5678',
      'matrix' => { 'rows' => 8, 'cols' => 7 },
      'vial_protocol' => 6,
      'via_protocol' => 12
    }))

    # position_map.yaml (最小限)
    File.write("#{config_dir}/position_map.yaml", YAML.dump({
      'left_hand' => {
        'row0' => ['A', 'B', 'C', 'D', 'E', 'F'],
        'row1' => [],
        'row2' => [],
        'row3' => [],
        'thumb_keys' => []
      },
      'right_hand' => {
        'row0' => [],
        'row1' => [],
        'row2' => [],
        'row3' => [],
        'thumb_keys' => []
      },
      'encoders' => {
        'left' => { 'push' => 'push', 'ccw' => 'ccw', 'cw' => 'cw' },
        'right' => { 'push' => 'push', 'ccw' => 'ccw', 'cw' => 'cw' }
      }
    }))

    # settings/qmk_settings.yaml
    File.write("#{config_dir}/settings/qmk_settings.yaml", YAML.dump({}))

    # layers/0_base.yaml
    File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
      'name' => 'Base',
      'description' => 'Base layer',
      'index' => 0,
      'mapping' => {
        'left_hand' => {
          'row0' => { 'A' => 'KC_A', 'B' => 'KC_B' },
          'row1' => {},
          'row2' => {},
          'row3' => {},
          'thumb_keys' => {}
        },
        'right_hand' => {
          'row0' => {},
          'row1' => {},
          'row2' => {},
          'row3' => {},
          'thumb_keys' => {}
        },
        'encoders' => {
          'left' => {},
          'right' => {}
        }
      }
    }))
  end

  it 'コンパイルして有効なlayout.vilを生成' do
    create_minimal_config

    compiler = Cornix::Compiler.new(config_dir)
    compiler.compile(output_path)

    expect(File.exist?(output_path)).to be true

    json_content = File.read(output_path)
    parsed = JSON.parse(json_content)

    expect(parsed['version']).to eq(1)
    expect(parsed['uid']).to eq('TEST123')
    expect(parsed['layout']).to be_an(Array)
    expect(parsed['layout'].size).to eq(10)
    expect(parsed['encoder_layout'].size).to eq(10)
    expect(parsed['macro'].size).to eq(32)
    expect(parsed['tap_dance'].size).to eq(32)
    expect(parsed['combo'].size).to eq(32)
  end

  it '実際のconfigディレクトリをコンパイル可能' do
    real_config_dir = File.join(__dir__, '../../config')
    skip "config/ not found" unless Dir.exist?(real_config_dir)
    skip "position_map.yaml not found" unless File.exist?("#{real_config_dir}/position_map.yaml")

    compiler = Cornix::Compiler.new(real_config_dir)
    compiler.compile(output_path)

    expect(File.exist?(output_path)).to be true

    json_content = File.read(output_path)
    parsed = JSON.parse(json_content)

    expect(parsed['version']).to be_a(Integer)
    expect(parsed['uid']).to be_a(Integer).or be_a(String)
    expect(parsed['layout'].size).to eq(10)
  end
end
