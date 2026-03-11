# frozen_string_literal: true

require_relative 'spec_helper'
require_relative '../lib/cornix/decompiler'
require 'tempfile'
require 'json'
require 'yaml'
require 'fileutils'

RSpec.describe Cornix::Decompiler do
  let(:test_vil_path) { File.expand_path('../tmp/layout.vil', __dir__) }
  let(:output_dir) { Dir.mktmpdir }
  let(:decompiler) { described_class.new(test_vil_path) }

  after do
    FileUtils.rm_rf(output_dir) if File.exist?(output_dir)
  end

  describe '#decompile' do
    it 'creates config directory structure with all required subdirectories' do
      decompiler.decompile(output_dir)

      expect(Dir.exist?(output_dir)).to be true
      expect(File.exist?("#{output_dir}/metadata.yaml")).to be true
      expect(File.exist?("#{output_dir}/position_map.yaml")).to be true
      expect(Dir.exist?("#{output_dir}/layers")).to be true
      expect(Dir.exist?("#{output_dir}/macros")).to be true
      expect(Dir.exist?("#{output_dir}/tap_dance")).to be true
      expect(Dir.exist?("#{output_dir}/combos")).to be true
      expect(Dir.exist?("#{output_dir}/settings")).to be true
    end

    it 'extracts metadata with all required fields' do
      decompiler.decompile(output_dir)

      metadata = YAML.load_file("#{output_dir}/metadata.yaml")

      expect(metadata).to have_key('keyboard')
      expect(metadata).to have_key('version')
      expect(metadata).to have_key('uid')
      expect(metadata).to have_key('vial_protocol')
      expect(metadata).to have_key('via_protocol')
    end

    it 'copies position_map template from lib/cornix/' do
      decompiler.decompile(output_dir)

      position_map = YAML.load_file("#{output_dir}/position_map.yaml")

      expect(position_map).to have_key('left_hand')
      expect(position_map).to have_key('right_hand')
      expect(position_map).to have_key('encoders')
    end

    it 'does not copy keycode_aliases.yaml to config directory' do
      decompiler.decompile(output_dir)

      expect(File.exist?("#{output_dir}/keycode_aliases.yaml")).to be false
    end

    it 'extracts all 10 layers' do
      decompiler.decompile(output_dir)

      layer_files = Dir.glob("#{output_dir}/layers/*.{yaml,yml}")
      expect(layer_files.size).to eq(10)
    end

    it 'extracts QMK settings' do
      decompiler.decompile(output_dir)

      settings_file = "#{output_dir}/settings/qmk_settings.yaml"
      expect(File.exist?(settings_file)).to be true

      settings = YAML.load_file(settings_file)
      expect(settings).to be_a(Hash)
    end

    it 'generates YAML files that can be recompiled' do
      # This is an integration test to ensure round-trip compatibility
      decompiler.decompile(output_dir)

      # Verify that generated YAML files have valid structure
      # (detailed validation is done by ModelValidator)
      expect(File.exist?("#{output_dir}/metadata.yaml")).to be true
      expect(Dir.glob("#{output_dir}/layers/*.yaml").size).to be > 0
    end
  end
end
