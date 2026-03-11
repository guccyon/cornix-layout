# frozen_string_literal: true

require_relative 'spec_helper'
require_relative '../lib/cornix/compiler'
require_relative '../lib/cornix/decompiler'
require 'json'
require 'tempfile'
require 'fileutils'

RSpec.describe 'Compiler and Decompiler Integration' do
  let(:test_config_dir) { File.expand_path('../config', __dir__) }
  let(:vil_file) { Tempfile.new(['test', '.vil']) }
  let(:temp_config_dir) { Dir.mktmpdir }

  after do
    vil_file.close
    vil_file.unlink
    FileUtils.rm_rf(temp_config_dir)
  end

  describe 'round-trip conversion' do
    it 'compiles YAML config to valid layout.vil' do
      compiler = Cornix::Compiler.new(test_config_dir)
      compiler.compile(vil_file.path)

      expect(File.exist?(vil_file.path)).to be true

      vil_data = JSON.parse(File.read(vil_file.path))

      # Verify essential structure
      expect(vil_data).to have_key('version')
      expect(vil_data).to have_key('layout')
      expect(vil_data).to have_key('macro')
      expect(vil_data).to have_key('tap_dance')
      expect(vil_data).to have_key('combo')

      # Verify layout has 10 layers
      expect(vil_data['layout'].size).to eq(10)
    end

    it 'maintains data integrity through full compile → decompile → compile round-trip' do
      # Step 1: Compile original config to vil
      compiler = Cornix::Compiler.new(test_config_dir)
      compiler.compile(vil_file.path)

      original_vil = JSON.parse(File.read(vil_file.path))

      # Step 2: Decompile to new config directory
      decompiler = Cornix::Decompiler.new(vil_file.path)
      decompiler.decompile(temp_config_dir)

      # Step 3: Recompile from new config
      vil_file2 = Tempfile.new(['test2', '.vil'])
      begin
        compiler2 = Cornix::Compiler.new(temp_config_dir)
        compiler2.compile(vil_file2.path)

        recompiled_vil = JSON.parse(File.read(vil_file2.path))

        # Step 4: Compare layouts (main content)
        expect(recompiled_vil['layout']).to eq(original_vil['layout'])
        expect(recompiled_vil['encoder_layout']).to eq(original_vil['encoder_layout'])
        expect(recompiled_vil['macro']).to eq(original_vil['macro'])
        expect(recompiled_vil['tap_dance']).to eq(original_vil['tap_dance'])
        expect(recompiled_vil['combo']).to eq(original_vil['combo'])
      ensure
        vil_file2.close
        vil_file2.unlink
      end
    end

    it 'decompiles layout.vil to YAML config directory' do
      # First compile to create a vil file
      compiler = Cornix::Compiler.new(test_config_dir)
      compiler.compile(vil_file.path)

      # Then decompile
      decompiler = Cornix::Decompiler.new(vil_file.path)
      decompiler.decompile(temp_config_dir)

      # Verify directory structure
      expect(Dir.exist?(temp_config_dir)).to be true
      expect(File.exist?("#{temp_config_dir}/metadata.yaml")).to be true
      expect(File.exist?("#{temp_config_dir}/position_map.yaml")).to be true
      expect(Dir.glob("#{temp_config_dir}/layers/*.yaml").size).to eq(10)
    end
  end
end
