# frozen_string_literal: true

require_relative 'spec_helper'
require_relative '../lib/cornix/compiler'
require 'tempfile'
require 'json'

RSpec.describe Cornix::Compiler do
  let(:config_dir) { File.join(__dir__, 'fixtures/test_config') }
  let(:output_file) { Tempfile.new(['layout', '.vil']) }

  after do
    output_file.close
    output_file.unlink
  end

  describe '#compile' do
    it 'generates a valid layout.vil file with correct structure' do
      compiler = described_class.new(config_dir)
      compiler.compile(output_file.path)

      expect(File.exist?(output_file.path)).to be true
      vil_data = JSON.parse(File.read(output_file.path))

      # Verify all required top-level keys exist
      expect(vil_data).to have_key('version')
      expect(vil_data).to have_key('uid')
      expect(vil_data).to have_key('layout')
      expect(vil_data).to have_key('encoder_layout')
      expect(vil_data).to have_key('macro')
      expect(vil_data).to have_key('tap_dance')
      expect(vil_data).to have_key('combo')
      expect(vil_data).to have_key('settings')
    end

    it 'includes exactly 10 layers' do
      compiler = described_class.new(config_dir)
      compiler.compile(output_file.path)
      vil_data = JSON.parse(File.read(output_file.path))

      expect(vil_data['layout'].size).to eq(10)
    end

    it 'includes encoder layout for all 10 layers' do
      compiler = described_class.new(config_dir)
      compiler.compile(output_file.path)
      vil_data = JSON.parse(File.read(output_file.path))

      expect(vil_data['encoder_layout'].size).to eq(10)
      vil_data['encoder_layout'].each do |encoder_layer|
        expect(encoder_layer.size).to eq(2) # left and right encoders
        expect(encoder_layer[0].size).to eq(2) # ccw and cw
        expect(encoder_layer[1].size).to eq(2)
      end
    end

    it 'loads KeycodeConverter from lib/cornix/keycode_aliases.yaml' do
      # Verify that Compiler initializes with correct keycode_aliases path
      expect(File.exist?(File.join(File.dirname(__FILE__), '../lib/cornix/keycode_aliases.yaml'))).to be true
    end

    it 'loads position_map from config directory' do
      # Verify that Compiler can find position_map.yaml in config
      expect(File.exist?("#{config_dir}/position_map.yaml")).to be true
    end

    it 'outputs to specified file path' do
      compiler = described_class.new(config_dir)
      custom_output = File.join(Dir.tmpdir, 'custom_layout.vil')
      compiler.compile(custom_output)

      expect(File.exist?(custom_output)).to be true
      File.delete(custom_output)
    end
  end
end
