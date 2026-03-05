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
    it 'compiles and decompiles without data loss' do
      # Compile YAML to vil
      compiler = Cornix::Compiler.new(test_config_dir)
      compiler.compile(vil_file.path)

      # Verify vil file was created
      expect(File.exist?(vil_file.path)).to be true

      # Parse vil file
      vil_data = JSON.parse(File.read(vil_file.path))

      # Verify structure
      expect(vil_data).to have_key('version')
      expect(vil_data).to have_key('layout')
      expect(vil_data).to have_key('macro')
      expect(vil_data).to have_key('tap_dance')
      expect(vil_data).to have_key('combo')

      # Verify layout has 10 layers
      expect(vil_data['layout'].size).to eq(10)

      # Verify macros (at least one should exist)
      non_empty_macros = vil_data['macro'].reject(&:empty?)
      expect(non_empty_macros.size).to be > 0
    end

    it 'maintains data integrity through full round-trip' do
      # Step 1: Compile original config to vil
      compiler = Cornix::Compiler.new(test_config_dir)
      compiler.compile(vil_file.path)

      original_vil = JSON.parse(File.read(vil_file.path))

      # Step 2: Decompile to new config
      decompiler = Cornix::Decompiler.new(vil_file.path)
      decompiler.decompile(temp_config_dir)

      # Step 3: Recompile from new config
      vil_file2 = Tempfile.new(['test2', '.vil'])
      compiler2 = Cornix::Compiler.new(temp_config_dir)
      compiler2.compile(vil_file2.path)

      recompiled_vil = JSON.parse(File.read(vil_file2.path))

      # Compare critical sections
      expect(recompiled_vil['version']).to eq(original_vil['version'])
      expect(recompiled_vil['uid']).to eq(original_vil['uid'])
      expect(recompiled_vil['layout']).to eq(original_vil['layout'])
      expect(recompiled_vil['encoder_layout']).to eq(original_vil['encoder_layout'])
      expect(recompiled_vil['macro']).to eq(original_vil['macro'])
      expect(recompiled_vil['tap_dance']).to eq(original_vil['tap_dance'])
      expect(recompiled_vil['combo']).to eq(original_vil['combo'])

      vil_file2.close
      vil_file2.unlink
    end
  end

  describe 'layer compilation' do
    it 'includes Layer 0 with all keycodes' do
      compiler = Cornix::Compiler.new(test_config_dir)
      compiler.compile(vil_file.path)

      vil_data = JSON.parse(File.read(vil_file.path))
      layer0 = vil_data['layout'][0]

      # Layer 0 should have 8 rows (4 left + 4 right)
      expect(layer0.size).to eq(8)

      # Each row should have 7 keys
      layer0.each do |row|
        expect(row.size).to eq(7)
      end

      # Check some specific keys exist
      # row0, col0 (left hand, tab) should be KC_TAB
      expect(layer0[0][0]).to eq('KC_TAB')
    end

    it 'handles override layers correctly' do
      compiler = Cornix::Compiler.new(test_config_dir)
      compiler.compile(vil_file.path)

      vil_data = JSON.parse(File.read(vil_file.path))
      layer0 = vil_data['layout'][0]
      layer1 = vil_data['layout'][1]

      # Layer 1 should be different from Layer 0
      expect(layer1).not_to eq(layer0)

      # But should have same structure
      expect(layer1.size).to eq(8)
      layer1.each do |row|
        expect(row.size).to eq(7)
      end
    end
  end

  describe 'macro compilation' do
    it 'compiles macros with correct indices' do
      compiler = Cornix::Compiler.new(test_config_dir)
      compiler.compile(vil_file.path)

      vil_data = JSON.parse(File.read(vil_file.path))
      macros = vil_data['macro']

      # Should have 32 macro slots
      expect(macros.size).to eq(32)

      # Check that non-empty macros are at their specified indices
      Dir.glob("#{test_config_dir}/macros/*.{yaml,yml}").each do |file|
        macro_config = YAML.load_file(file)
        next unless macro_config['enabled']

        index = macro_config['index']
        expect(macros[index]).not_to be_empty
      end
    end
  end

  describe 'alias resolution' do
    it 'correctly handles layer number arguments' do
      compiler = Cornix::Compiler.new(test_config_dir)
      compiler.compile(vil_file.path)

      vil_data = JSON.parse(File.read(vil_file.path))

      # MO(3) should stay as MO(3), not become MO(KC_3)
      layer0 = vil_data['layout'][0]
      mo_keycodes = layer0.flatten.grep(/^MO\(\d+\)$/)
      expect(mo_keycodes).not_to be_empty

      mo_keycodes.each do |keycode|
        # Should be MO(N) not MO(KC_N)
        expect(keycode).not_to match(/KC_\d+/)
      end
    end
  end
end
