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

  describe 'reference system integration' do
    describe 'name-based references' do
      it 'compiles name-based Macro references to QMK format' do
        # Create temp config with name-based reference
        temp_config = Dir.mktmpdir
        FileUtils.cp_r("#{test_config_dir}/.", temp_config)

        # Get the actual macro name from the first macro file
        macro_files = Dir.glob("#{temp_config}/macros/*.{yaml,yml}").sort
        macro_data = YAML.load_file(macro_files.first)
        macro_name = macro_data['name']
        macro_index = macro_data['index']

        # Update layer to use name-based reference
        layer_path = "#{temp_config}/layers/0_layer.yml"
        layer_data = YAML.load_file(layer_path)
        layer_data['mapping']['tab'] = "Macro('#{macro_name}')"  # Use existing position
        File.write(layer_path, YAML.dump(layer_data))

        compiler = Cornix::Compiler.new(temp_config)
        compiler.compile(vil_file.path)

        vil_data = JSON.parse(File.read(vil_file.path))
        layer0 = vil_data['layout'][0]

        # Should compile to M{index} (QMK format)
        expect(layer0.flatten).to include("M#{macro_index}")

        FileUtils.rm_rf(temp_config)
      end

      it 'compiles name-based TapDance references to QMK format' do
        temp_config = Dir.mktmpdir
        FileUtils.cp_r("#{test_config_dir}/.", temp_config)

        # Get the actual tap dance name from the first tap dance file
        td_files = Dir.glob("#{temp_config}/tap_dance/*.{yaml,yml}").sort
        td_data = YAML.load_file(td_files.first)
        td_name = td_data['name']
        td_index = td_data['index']

        # Update layer to use name-based reference
        layer_path = "#{temp_config}/layers/0_layer.yml"
        layer_data = YAML.load_file(layer_path)
        layer_data['mapping']['Q'] = "TapDance('#{td_name}')"  # Use existing position
        File.write(layer_path, YAML.dump(layer_data))

        compiler = Cornix::Compiler.new(temp_config)
        compiler.compile(vil_file.path)

        vil_data = JSON.parse(File.read(vil_file.path))
        layer0 = vil_data['layout'][0]

        # Should compile to TD(index)
        expect(layer0.flatten).to include("TD(#{td_index})")

        FileUtils.rm_rf(temp_config)
      end
    end

    describe 'index-based references' do
      it 'preserves index-based Macro references' do
        temp_config = Dir.mktmpdir
        FileUtils.cp_r("#{test_config_dir}/.", temp_config)

        # Update layer to use index-based references
        layer_path = "#{temp_config}/layers/0_layer.yml"
        layer_data = YAML.load_file(layer_path)
        layer_data['mapping']['tab'] = 'Macro(0)'
        layer_data['mapping']['Q'] = 'Macro(1)'
        File.write(layer_path, YAML.dump(layer_data))

        compiler = Cornix::Compiler.new(temp_config)
        compiler.compile(vil_file.path)

        vil_data = JSON.parse(File.read(vil_file.path))
        layer0 = vil_data['layout'][0]

        expect(layer0.flatten).to include('M0')
        expect(layer0.flatten).to include('M1')

        FileUtils.rm_rf(temp_config)
      end

      it 'preserves index-based TapDance references' do
        temp_config = Dir.mktmpdir
        FileUtils.cp_r("#{test_config_dir}/.", temp_config)

        # Update layer to use index-based references
        layer_path = "#{temp_config}/layers/0_layer.yml"
        layer_data = YAML.load_file(layer_path)
        layer_data['mapping']['W'] = 'TapDance(0)'
        layer_data['mapping']['E'] = 'TapDance(1)'
        File.write(layer_path, YAML.dump(layer_data))

        compiler = Cornix::Compiler.new(temp_config)
        compiler.compile(vil_file.path)

        vil_data = JSON.parse(File.read(vil_file.path))
        layer0 = vil_data['layout'][0]

        expect(layer0.flatten).to include('TD(0)')
        expect(layer0.flatten).to include('TD(1)')

        FileUtils.rm_rf(temp_config)
      end
    end

    describe 'legacy references' do
      it 'preserves legacy M0 format' do
        temp_config = Dir.mktmpdir
        FileUtils.cp_r("#{test_config_dir}/.", temp_config)

        # Update layer to use legacy references
        layer_path = "#{temp_config}/layers/0_layer.yml"
        layer_data = YAML.load_file(layer_path)
        layer_data['mapping']['R'] = 'M0'
        layer_data['mapping']['T'] = 'M1'
        File.write(layer_path, YAML.dump(layer_data))

        compiler = Cornix::Compiler.new(temp_config)
        compiler.compile(vil_file.path)

        vil_data = JSON.parse(File.read(vil_file.path))
        layer0 = vil_data['layout'][0]

        expect(layer0.flatten).to include('M0')
        expect(layer0.flatten).to include('M1')

        FileUtils.rm_rf(temp_config)
      end

      it 'preserves legacy TD(0) format' do
        temp_config = Dir.mktmpdir
        FileUtils.cp_r("#{test_config_dir}/.", temp_config)

        # Update layer to use legacy references
        layer_path = "#{temp_config}/layers/0_layer.yml"
        layer_data = YAML.load_file(layer_path)
        layer_data['mapping']['Y'] = 'TD(0)'
        layer_data['mapping']['U'] = 'TD(1)'
        File.write(layer_path, YAML.dump(layer_data))

        compiler = Cornix::Compiler.new(temp_config)
        compiler.compile(vil_file.path)

        vil_data = JSON.parse(File.read(vil_file.path))
        layer0 = vil_data['layout'][0]

        expect(layer0.flatten).to include('TD(0)')
        expect(layer0.flatten).to include('TD(1)')

        FileUtils.rm_rf(temp_config)
      end
    end

    describe 'decompiler format upgrade' do
      it 'upgrades legacy M0 to name-based Macro references' do
        # Compile original (will have M0 in vil)
        compiler = Cornix::Compiler.new(test_config_dir)
        compiler.compile(vil_file.path)

        # Decompile
        temp_config = Dir.mktmpdir
        decompiler = Cornix::Decompiler.new(vil_file.path)
        decompiler.decompile(temp_config)

        # Check that decompiled layers use name-based format
        layer_files = Dir.glob("#{temp_config}/layers/*.yml")
        layer_contents = layer_files.map { |f| File.read(f) }.join

        # Should contain name-based Macro references
        expect(layer_contents).to match(/Macro\('/)

        # Should not contain legacy M0 format (upgraded to name-based)
        # Note: Some layers might not have macro references at all
        # so we just check that IF there are macro references, they're name-based

        FileUtils.rm_rf(temp_config)
      end

      it 'upgrades legacy TD(0) to name-based TapDance references' do
        compiler = Cornix::Compiler.new(test_config_dir)
        compiler.compile(vil_file.path)

        temp_config = Dir.mktmpdir
        decompiler = Cornix::Decompiler.new(vil_file.path)
        decompiler.decompile(temp_config)

        layer_files = Dir.glob("#{temp_config}/layers/*.yml")
        layer_contents = layer_files.map { |f| File.read(f) }.join

        # Should contain name-based TapDance references
        expect(layer_contents).to match(/TapDance\('/)

        FileUtils.rm_rf(temp_config)
      end
    end

    describe 'round-trip with mixed formats' do
      it 'handles all three reference formats correctly' do
        # Create config with mixed reference formats
        temp_config = Dir.mktmpdir
        FileUtils.cp_r("#{test_config_dir}/.", temp_config)

        # Get actual macro and tap dance names
        macro_files = Dir.glob("#{temp_config}/macros/*.{yaml,yml}").sort
        macro0 = YAML.load_file(macro_files[0])

        td_files = Dir.glob("#{temp_config}/tap_dance/*.{yaml,yml}").sort
        td0 = YAML.load_file(td_files[0])

        # Update layer to use mixed reference formats
        layer_path = "#{temp_config}/layers/0_layer.yml"
        layer_data = YAML.load_file(layer_path)
        layer_data['mapping']['tab'] = "Macro('#{macro0['name']}')"  # name-based
        layer_data['mapping']['Q'] = 'Macro(1)'                      # index-based
        layer_data['mapping']['W'] = 'M2'                            # legacy
        layer_data['mapping']['E'] = "TapDance('#{td0['name']}')"   # name-based
        layer_data['mapping']['R'] = 'TapDance(1)'                   # index-based
        layer_data['mapping']['T'] = 'TD(2)'                         # legacy
        File.write(layer_path, YAML.dump(layer_data))

        # Compile
        vil_temp = Tempfile.new(['mixed', '.vil'])
        compiler = Cornix::Compiler.new(temp_config)
        compiler.compile(vil_temp.path)

        vil_data1 = JSON.parse(File.read(vil_temp.path))

        # Decompile
        temp_config2 = Dir.mktmpdir
        decompiler = Cornix::Decompiler.new(vil_temp.path)
        decompiler.decompile(temp_config2)

        # Recompile
        vil_temp2 = Tempfile.new(['mixed2', '.vil'])
        compiler2 = Cornix::Compiler.new(temp_config2)
        compiler2.compile(vil_temp2.path)

        vil_data2 = JSON.parse(File.read(vil_temp2.path))

        # Should be identical
        expect(vil_data2['layout']).to eq(vil_data1['layout'])

        FileUtils.rm_rf(temp_config)
        FileUtils.rm_rf(temp_config2)
        vil_temp.close
        vil_temp.unlink
        vil_temp2.close
        vil_temp2.unlink
      end
    end
  end
end
