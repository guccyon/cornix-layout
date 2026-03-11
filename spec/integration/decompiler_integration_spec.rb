# frozen_string_literal: true

require_relative '../spec_helper'
require_relative '../../lib/cornix/decompiler'
require_relative '../../lib/cornix/compiler'
require 'fileutils'
require 'tempfile'
require 'json'

RSpec.describe 'Decompiler Integration' do
  let(:temp_dir) { Dir.mktmpdir }
  let(:vil_path) { File.join(temp_dir, 'layout.vil') }
  let(:config_dir) { File.join(temp_dir, 'config') }

  after do
    FileUtils.rm_rf(temp_dir)
  end

  def create_minimal_vil
    vil_data = {
      'version' => 1,
      'uid' => 'TEST123',
      'vendor_product_id' => '0x1234:0x5678',
      'product_id' => '0x5678',
      'matrix' => { 'rows' => 8, 'cols' => 7 },
      'vial_protocol' => 6,
      'via_protocol' => 12,
      'layout' => Array.new(10) { Array.new(8) { Array.new(7, -1) } },
      'encoder_layout' => Array.new(10) { [[-1, -1], [-1, -1]] },
      'macro' => Array.new(32) { [] },
      'tap_dance' => Array.new(32) { [-1, -1, -1, -1, 200] },
      'combo' => Array.new(32) { [-1, -1, -1, -1, -1] },
      'settings' => {}
    }
    File.write(vil_path, JSON.generate(vil_data))
  end

  it 'decompileして有効なYAML設定を生成' do
    create_minimal_vil

    decompiler = Cornix::Decompiler.new(vil_path)
    decompiler.decompile(config_dir)

    expect(Dir.exist?(config_dir)).to be true
    expect(File.exist?("#{config_dir}/metadata.yaml")).to be true
    expect(Dir.exist?("#{config_dir}/layers")).to be true
    expect(Dir.exist?("#{config_dir}/macros")).to be true
    expect(Dir.exist?("#{config_dir}/tap_dance")).to be true
    expect(Dir.exist?("#{config_dir}/combos")).to be true
  end

  it '実際のlayout.vilをdecompile可能' do
    real_vil_path = File.join(__dir__, '../../tmp/layout.vil')
    skip "tmp/layout.vil not found" unless File.exist?(real_vil_path)

    decompiler = Cornix::Decompiler.new(real_vil_path)
    decompiler.decompile(config_dir)

    expect(Dir.exist?(config_dir)).to be true

    metadata = YAML.load_file("#{config_dir}/metadata.yaml")
    expect(metadata['version']).to be_a(Integer)
  end

  it 'decompile後にrecompile可能（round-trip）' do
    create_minimal_vil

    # Decompile
    decompiler = Cornix::Decompiler.new(vil_path)
    decompiler.decompile(config_dir)

    # Recompile
    recompiled_path = File.join(temp_dir, 'recompiled.vil')
    compiler = Cornix::Compiler.new(config_dir)
    compiler.compile(recompiled_path)

    expect(File.exist?(recompiled_path)).to be true

    # 基本構造が一致するか確認
    original = JSON.parse(File.read(vil_path))
    recompiled = JSON.parse(File.read(recompiled_path))

    expect(recompiled['version']).to eq(original['version'])
    expect(recompiled['uid']).to eq(original['uid'])
    expect(recompiled['layout'].size).to eq(10)
  end
end
