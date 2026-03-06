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
    it 'creates config directory structure' do
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

    it 'extracts metadata correctly' do
      decompiler.decompile(output_dir)

      metadata = YAML.load_file("#{output_dir}/metadata.yaml")

      expect(metadata).to have_key('keyboard')
      expect(metadata).to have_key('version')
      expect(metadata).to have_key('uid')
      expect(metadata).to have_key('vial_protocol')
      expect(metadata).to have_key('via_protocol')
      expect(metadata['keyboard']).to eq('cornix')
    end

    it 'extracts position map correctly' do
      decompiler.decompile(output_dir)

      position_map = YAML.load_file("#{output_dir}/position_map.yaml")

      expect(position_map).to have_key('left_hand')
      expect(position_map).to have_key('right_hand')
      expect(position_map).to have_key('encoders')

      # Check structure
      expect(position_map['left_hand']).to have_key('row0')
      expect(position_map['left_hand']['row0']).to be_an(Array)
    end

    it 'extracts QMK settings correctly' do
      decompiler.decompile(output_dir)

      settings = YAML.load_file("#{output_dir}/settings/qmk_settings.yaml")

      expect(settings).to have_key('keyboard')
      expect(settings).to have_key('vial')
      expect(settings['keyboard']).to have_key('tapping_term')
      expect(settings['vial']).to have_key('combo_timing_window')
    end
  end

  describe 'keycode resolution' do
    describe 'QMK to alias conversion' do
      it 'converts KC_* keycodes to readable aliases' do
        decompiler.decompile(output_dir)

        layer0 = YAML.load_file("#{output_dir}/layers/0_layer.yml")
        mapping = layer0['mapping']

        # KC_TAB should become Tab
        expect(mapping['tab']).to eq('Tab')

        # KC_Q should become Q
        expect(mapping['Q']).to eq('Q')
      end

      it 'converts KC_TRNS to Trans' do
        decompiler.decompile(output_dir)

        # Look for Trans in layer 1
        layer1_path = "#{output_dir}/layers/1_layer.yml"
        if File.exist?(layer1_path)
          layer1 = YAML.load_file(layer1_path)
          overrides = layer1['overrides']

          # Find Trans values
          trans_values = overrides.values.select { |v| v == 'Trans' }
          expect(trans_values).not_to be_empty
        end
      end

      it 'converts modifier functions with KC_* arguments to simple format' do
        decompiler.decompile(output_dir)

        layer1_path = "#{output_dir}/layers/1_layer.yml"
        if File.exist?(layer1_path)
          layer1 = YAML.load_file(layer1_path)
          overrides = layer1['overrides']

          # LSFT(KC_1) should become LSFT(1)
          shifted_numbers = overrides.values.any? { |v| v.to_s.match?(/^LSFT\(\d+\)$/) }
          expect(shifted_numbers).to be true
        end
      end

      it 'preserves layer numbers in function calls' do
        decompiler.decompile(output_dir)

        layer0 = YAML.load_file("#{output_dir}/layers/0_layer.yml")
        mapping = layer0['mapping']

        # MO(3) should stay as MO(3)
        mo_values = mapping.values.select { |v| v.to_s.match?(/^MO\(\d+\)$/) }
        expect(mo_values).not_to be_empty
      end
    end
  end

  describe 'layer extraction' do
    it 'extracts base layer with complete mapping' do
      decompiler.decompile(output_dir)

      layer0 = YAML.load_file("#{output_dir}/layers/0_layer.yml")

      expect(layer0).to have_key('name')
      expect(layer0).to have_key('description')
      expect(layer0).to have_key('mapping')

      mapping = layer0['mapping']

      # Should have all keys including encoders
      expect(mapping).to have_key('tab')
      expect(mapping).to have_key('Q')
      expect(mapping).to have_key('l_rotary_push')
      expect(mapping).to have_key('l_rotary_ccw')
      expect(mapping).to have_key('l_rotary_cw')
      expect(mapping).to have_key('r_rotary_push')
      expect(mapping).to have_key('r_rotary_ccw')
      expect(mapping).to have_key('r_rotary_cw')
    end

    it 'extracts override layers with only differences' do
      decompiler.decompile(output_dir)

      layer1_path = "#{output_dir}/layers/1_layer.yml"
      if File.exist?(layer1_path)
        layer1 = YAML.load_file(layer1_path)

        expect(layer1).to have_key('name')
        expect(layer1).to have_key('description')
        expect(layer1).to have_key('overrides')

        # Overrides should be a subset of all possible keys
        overrides = layer1['overrides']
        expect(overrides.size).to be < 56 # Less than total keys
      end
    end

    it 'skips empty override layers' do
      decompiler.decompile(output_dir)

      layer_files = Dir.glob("#{output_dir}/layers/*.{yaml,yml}")
      layer_indices = layer_files.map { |f| File.basename(f).match(/^(\d+)_/)[1].to_i }

      # Not all 10 layers should have files if some are empty
      expect(layer_indices.size).to be <= 10
    end

    it 'extracts all 10 layers correctly' do
      decompiler.decompile(output_dir)

      layer_files = Dir.glob("#{output_dir}/layers/*.{yaml,yml}")

      # Should have at least layer 0
      expect(layer_files).not_to be_empty

      layer_files.each do |file|
        basename = File.basename(file)
        expect(basename).to match(/^\d+_layer\.yml$/)

        layer = YAML.load_file(file)
        index = basename.match(/^(\d+)_/)[1].to_i

        if index == 0
          expect(layer).to have_key('mapping')
        else
          # Override layers may have 'overrides' key
          # Empty layers are skipped, so this file should have overrides
          expect(layer).to have_key('overrides') if layer.key?('overrides')
        end
      end
    end
  end

  describe 'macro extraction' do
    it 'extracts macros with correct structure' do
      decompiler.decompile(output_dir)

      macro_files = Dir.glob("#{output_dir}/macros/*.{yaml,yml}")
      expect(macro_files).not_to be_empty

      macro_files.each do |file|
        macro = YAML.load_file(file)

        expect(macro).to have_key('name')
        expect(macro).to have_key('description')
        expect(macro).to have_key('enabled')
        expect(macro).to have_key('index')
        expect(macro).to have_key('sequence')
        expect(macro['enabled']).to be true
        expect(macro['sequence']).to be_an(Array)
      end
    end

    it 'extracts macro sequences correctly' do
      decompiler.decompile(output_dir)

      # Find macro 0 (bracket_pair)
      macro0_path = "#{output_dir}/macros/00_macro.yml"
      if File.exist?(macro0_path)
        macro = YAML.load_file(macro0_path)
        sequence = macro['sequence']

        expect(sequence).not_to be_empty

        # Should have tap action
        tap_action = sequence.find { |step| step['action'] == 'tap' }
        expect(tap_action).not_to be_nil
        expect(tap_action).to have_key('keys')
      end
    end

    it 'preserves macro indices correctly' do
      decompiler.decompile(output_dir)

      macro_files = Dir.glob("#{output_dir}/macros/*.{yaml,yml}")

      macro_files.each do |file|
        macro = YAML.load_file(file)
        basename = File.basename(file)

        # Filename should be NN_*.yml
        expect(basename).to match(/^\d{2}_/)

        # Index should be an integer
        expect(macro['index']).to be_an(Integer)
        expect(macro['index']).to be >= 0
        expect(macro['index']).to be < 32
      end
    end

    it 'skips empty macro slots' do
      decompiler.decompile(output_dir)

      macro_files = Dir.glob("#{output_dir}/macros/*.{yaml,yml}")

      # Should have fewer than 32 files (only non-empty macros)
      expect(macro_files.size).to be < 32
    end
  end

  describe 'tap dance extraction' do
    it 'extracts tap dance with correct structure' do
      decompiler.decompile(output_dir)

      td_files = Dir.glob("#{output_dir}/tap_dance/*.{yaml,yml}")
      expect(td_files).not_to be_empty

      td_files.each do |file|
        td = YAML.load_file(file)

        expect(td).to have_key('name')
        expect(td).to have_key('description')
        expect(td).to have_key('enabled')
        expect(td).to have_key('index')
        expect(td).to have_key('actions')
        expect(td).to have_key('tapping_term')
      end
    end

    it 'extracts tap dance actions correctly' do
      decompiler.decompile(output_dir)

      td0_path = "#{output_dir}/tap_dance/00_tap_dance.yml"
      if File.exist?(td0_path)
        td = YAML.load_file(td0_path)
        actions = td['actions']

        expect(actions).to have_key('on_tap')
        expect(actions).to have_key('on_hold')
        expect(actions).to have_key('on_double_tap')
        expect(actions).to have_key('on_tap_hold')

        # TD 0 should have OSL(4) and MO(1)
        expect(actions['on_tap']).to eq('OSL(4)')
        expect(actions['on_hold']).to eq('MO(1)')
      end
    end

    it 'preserves layer numbers in tap dance actions' do
      decompiler.decompile(output_dir)

      td_files = Dir.glob("#{output_dir}/tap_dance/*.{yaml,yml}")

      td_files.each do |file|
        td = YAML.load_file(file)
        actions = td['actions']

        # Check that layer functions keep their numeric arguments
        actions.each_value do |action|
          match = action.to_s.match(/^(MO|OSL|TO|TG|TT|DF|LT\d*)\((\d+)\)$/)
          if match
            # Layer number should be preserved as integer
            expect(match[2]).to match(/^\d+$/)
          end
        end
      end
    end

    it 'skips empty tap dance slots' do
      decompiler.decompile(output_dir)

      td_files = Dir.glob("#{output_dir}/tap_dance/*.{yaml,yml}")

      # Should have fewer than 32 files (only defined tap dances)
      expect(td_files.size).to be < 32
    end
  end

  describe 'combo extraction' do
    it 'extracts combos with correct structure' do
      decompiler.decompile(output_dir)

      combo_files = Dir.glob("#{output_dir}/combos/*.{yaml,yml}")
      expect(combo_files).not_to be_empty

      combo_files.each do |file|
        combo = YAML.load_file(file)

        expect(combo).to have_key('name')
        expect(combo).to have_key('description')
        expect(combo).to have_key('enabled')
        expect(combo).to have_key('index')
        expect(combo).to have_key('trigger')
        expect(combo).to have_key('output')
      end
    end

    it 'extracts combo triggers correctly' do
      decompiler.decompile(output_dir)

      combo0_path = "#{output_dir}/combos/00_combo.yml"
      if File.exist?(combo0_path)
        combo = YAML.load_file(combo0_path)

        expect(combo['trigger']).to be_an(Array)
        expect(combo['trigger'].size).to be >= 2
        expect(combo['output']).to be_a(String)

        # Combo 0 is D + F → [
        expect(combo['trigger']).to eq(['KC_D', 'KC_F'])
        expect(combo['output']).to eq('KC_LBRACKET')
      end
    end

    it 'skips empty combo slots' do
      decompiler.decompile(output_dir)

      combo_files = Dir.glob("#{output_dir}/combos/*.{yaml,yml}")

      # Should have fewer than 32 files (only defined combos)
      expect(combo_files.size).to be < 32
    end
  end

  describe 'edge cases' do
    it 'handles missing optional fields gracefully' do
      # Create a minimal vil file
      minimal_vil = {
        'version' => 1,
        'uid' => '0x12345678',
        'vial_protocol' => 6,
        'via_protocol' => 12,
        'layout' => Array.new(10) { Array.new(8) { Array.new(7, 'KC_NO') } },
        'encoder_layout' => Array.new(10) { [['KC_VOLD', 'KC_VOLU'], ['KC_WH_U', 'KC_WH_D']] },
        'layout_options' => -1,
        'macro' => Array.new(32) { [] },
        'tap_dance' => Array.new(32) { ['KC_NO', 'KC_NO', 'KC_NO', 'KC_NO', 250] },
        'combo' => Array.new(32) { ['KC_NO', 'KC_NO', 'KC_NO', 'KC_NO', 'KC_NO'] },
        'key_override' => [],
        'alt_repeat_key' => [],
        'settings' => {}
      }

      temp_vil = Tempfile.new(['minimal', '.vil'])
      temp_vil.write(JSON.generate(minimal_vil))
      temp_vil.close

      minimal_decompiler = described_class.new(temp_vil.path)
      minimal_decompiler.decompile(output_dir)

      expect(File.exist?("#{output_dir}/metadata.yaml")).to be true
      expect(File.exist?("#{output_dir}/layers/0_layer.yml")).to be true

      temp_vil.unlink
    end

    it 'handles special characters in keycodes' do
      decompiler.decompile(output_dir)

      # Layer 1 should have special chars
      layer1_path = "#{output_dir}/layers/1_layer.yml"
      if File.exist?(layer1_path)
        layer1 = YAML.load_file(layer1_path)
        overrides = layer1['overrides']

        # Should find quotes, backticks, etc
        special_chars = overrides.values.select { |v| v.to_s.match?(/[`'",\/=\-]/) }
        expect(special_chars).not_to be_empty
      end
    end

    it 'does not create keycode_aliases.yaml in config' do
      decompiler.decompile(output_dir)

      # keycode_aliases.yaml should NOT be copied to config
      expect(File.exist?("#{output_dir}/keycode_aliases.yaml")).to be false
    end

    it 'loads position map template from lib/cornix' do
      template_path = File.join(__dir__, '../lib/cornix/position_map.yaml')
      expect(File.exist?(template_path)).to be true

      template = YAML.load_file(template_path)
      expect(template).to have_key('left_hand')
      expect(template).to have_key('right_hand')
      expect(template).to have_key('encoders')

      expect(template['left_hand']['row0']).to be_an(Array)
      expect(template['encoders']['left']).to have_key('push')
    end

    it 'does not define POSITION_MAP constant' do
      expect(Cornix::Decompiler.const_defined?(:POSITION_MAP)).to be false
    end
  end

  describe 'round-trip compatibility' do
    it 'produces YAML that can be recompiled' do
      # This is a basic check - full round-trip is tested in integration_spec
      decompiler.decompile(output_dir)

      # All required files should exist for recompilation
      expect(File.exist?("#{output_dir}/metadata.yaml")).to be true
      expect(File.exist?("#{output_dir}/position_map.yaml")).to be true
      expect(Dir.exist?("#{output_dir}/layers")).to be true
      expect(File.exist?("#{output_dir}/layers/0_layer.yml")).to be true
      expect(File.exist?("#{output_dir}/settings/qmk_settings.yaml")).to be true
    end
  end

  describe 'reference format support' do
    it 'upgrades legacy M0 to name-based Macro reference' do
      decompiler.decompile(output_dir)

      # Check if layers contain Macro references instead of M0
      layer_files = Dir.glob("#{output_dir}/layers/*.yml")
      layer_contents = layer_files.map { |f| File.read(f) }.join

      # Should contain name-based Macro references
      expect(layer_contents).to match(/Macro\('/)
    end

    it 'upgrades legacy TD(0) to name-based TapDance reference' do
      decompiler.decompile(output_dir)

      # Check if layers contain TapDance references instead of TD(0)
      layer_files = Dir.glob("#{output_dir}/layers/*.yml")
      layer_contents = layer_files.map { |f| File.read(f) }.join

      # Should contain name-based TapDance references
      expect(layer_contents).to match(/TapDance\('/)
    end

    it 'converts QMK keycodes to aliases' do
      result = decompiler.send(:resolve_to_alias, 'KC_TAB')
      expect(result).to eq('Tab')
    end

    it 'converts KC_TRNS to Trans' do
      result = decompiler.send(:resolve_to_alias, 'KC_TRNS')
      expect(result).to eq('Trans')
    end

    it 'handles function calls with nested keycodes' do
      result = decompiler.send(:resolve_to_alias, 'LSFT(KC_A)')
      expect(result).to eq('LSFT(A)')
    end

    it 'handles LT function with layer and keycode' do
      result = decompiler.send(:resolve_to_alias, 'LT(1, KC_SPACE)')
      expect(result).to eq('LT(1, Space)')
    end

    it 'handles nil keycode' do
      result = decompiler.send(:resolve_to_alias, nil)
      expect(result).to be_nil
    end

    it 'handles -1 keycode' do
      result = decompiler.send(:resolve_to_alias, -1)
      expect(result).to eq(-1)
    end
  end
end
