# frozen_string_literal: true

require_relative 'spec_helper'
require_relative '../lib/cornix/compiler'
require 'tempfile'
require 'json'
require 'yaml'
require 'fileutils'

RSpec.describe Cornix::Compiler do
  let(:config_dir) { File.expand_path('../config', __dir__) }
  let(:output_file) { Tempfile.new(['layout', '.vil']) }
  let(:compiler) { described_class.new(config_dir) }

  after do
    output_file.close
    output_file.unlink
  end

  describe '#compile' do
    it 'generates a valid layout.vil file' do
      compiler.compile(output_file.path)

      expect(File.exist?(output_file.path)).to be true
      vil_data = JSON.parse(File.read(output_file.path))

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
      compiler.compile(output_file.path)
      vil_data = JSON.parse(File.read(output_file.path))

      expect(vil_data['layout'].size).to eq(10)
    end

    it 'includes encoder layout for all 10 layers' do
      compiler.compile(output_file.path)
      vil_data = JSON.parse(File.read(output_file.path))

      expect(vil_data['encoder_layout'].size).to eq(10)
      vil_data['encoder_layout'].each do |encoder_layer|
        expect(encoder_layer.size).to eq(2) # left and right encoders
        expect(encoder_layer[0].size).to eq(2) # ccw and cw
        expect(encoder_layer[1].size).to eq(2)
      end
    end
  end

  describe 'keycode resolution' do
    describe 'alias to QMK conversion' do
      it 'converts basic aliases to QMK keycodes' do
        compiler.compile(output_file.path)
        vil_data = JSON.parse(File.read(output_file.path))
        layer0 = vil_data['layout'][0]

        # Tab key at position [0][0]
        expect(layer0[0][0]).to eq('KC_TAB')
      end

      it 'converts transparent aliases to KC_TRNS' do
        compiler.compile(output_file.path)
        vil_data = JSON.parse(File.read(output_file.path))
        layer1 = vil_data['layout'][1]

        # Check for KC_TRNS in layer 1
        trans_found = layer1.flatten.include?('KC_TRNS')
        expect(trans_found).to be true
      end

      it 'converts function keycodes with layer numbers correctly' do
        compiler.compile(output_file.path)
        vil_data = JSON.parse(File.read(output_file.path))
        layer0 = vil_data['layout'][0]

        # MO(3) should remain as MO(3), not MO(KC_3)
        mo_found = layer0.flatten.any? { |k| k.to_s.match?(/^MO\(\d+\)$/) }
        expect(mo_found).to be true
      end

      it 'converts modifier function keycodes with number arguments to KC_* format' do
        compiler.compile(output_file.path)
        vil_data = JSON.parse(File.read(output_file.path))
        layer1 = vil_data['layout'][1]

        # LSFT(1) should become LSFT(KC_1)
        # Find a cell with LSFT(KC_1)
        lsft_found = layer1.flatten.any? { |k| k.to_s.match?(/^LSFT\(KC_\d+\)$/) }
        expect(lsft_found).to be true
      end

      it 'handles nested function calls correctly' do
        compiler.compile(output_file.path)
        vil_data = JSON.parse(File.read(output_file.path))

        # LT(1, Space) should become LT(1, KC_SPACE)
        # LGUI_T(KC_LANG2) should remain as is
        layer0 = vil_data['layout'][0]
        lt_found = layer0.flatten.any? { |k| k.to_s.match?(/^LT\d*\(/) }
        expect(lt_found).to be true
      end
    end

    describe 'layer compilation' do
      it 'generates base layer with all positions filled' do
        compiler.compile(output_file.path)
        vil_data = JSON.parse(File.read(output_file.path))
        layer0 = vil_data['layout'][0]

        # Should have 8 rows (4 left + 4 right)
        expect(layer0.size).to eq(8)

        # Each row should have 7 columns
        layer0.each do |row|
          expect(row.size).to eq(7)
        end
      end

      it 'generates override layers with only differences' do
        compiler.compile(output_file.path)
        vil_data = JSON.parse(File.read(output_file.path))
        layer0 = vil_data['layout'][0]
        layer1 = vil_data['layout'][1]

        # Layer 1 should have some keys different from layer 0
        differences = 0
        8.times do |row|
          7.times do |col|
            differences += 1 if layer0[row][col] != layer1[row][col]
          end
        end

        expect(differences).to be > 0
      end

      it 'handles rotary push buttons correctly' do
        compiler.compile(output_file.path)
        vil_data = JSON.parse(File.read(output_file.path))
        layer0 = vil_data['layout'][0]

        # Left rotary push at [2][6]
        expect(layer0[2][6]).not_to eq(-1)

        # Right rotary push at [5][6]
        expect(layer0[5][6]).not_to eq(-1)
      end
    end
  end

  describe 'encoder compilation' do
    it 'includes encoder definitions for all layers' do
      compiler.compile(output_file.path)
      vil_data = JSON.parse(File.read(output_file.path))

      vil_data['encoder_layout'].each_with_index do |encoder, idx|
        expect(encoder[0]).to be_an(Array) # left encoder
        expect(encoder[1]).to be_an(Array) # right encoder

        # Each encoder should have ccw and cw actions
        expect(encoder[0].size).to eq(2)
        expect(encoder[1].size).to eq(2)
      end
    end

    it 'uses default encoder values when not specified' do
      compiler.compile(output_file.path)
      vil_data = JSON.parse(File.read(output_file.path))

      # Layer 0 might have custom encoders, but check structure
      encoder_layer0 = vil_data['encoder_layout'][0]
      expect(encoder_layer0[0][0]).to match(/^KC_/) # ccw
      expect(encoder_layer0[0][1]).to match(/^KC_/) # cw
    end
  end

  describe 'macro compilation' do
    it 'compiles enabled macros into macro array' do
      compiler.compile(output_file.path)
      vil_data = JSON.parse(File.read(output_file.path))

      expect(vil_data['macro']).to be_an(Array)
      expect(vil_data['macro'].size).to eq(32)

      # At least one macro should be non-empty
      non_empty_macros = vil_data['macro'].reject(&:empty?)
      expect(non_empty_macros.size).to be > 0
    end

    it 'places macros at correct indices' do
      compiler.compile(output_file.path)
      vil_data = JSON.parse(File.read(output_file.path))

      # Macro at index 0 should exist (00_macro.yml with index: 0)
      expect(vil_data['macro'][0]).not_to be_empty
      expect(vil_data['macro'][0]).to be_an(Array)
    end

    it 'compiles tap actions correctly' do
      compiler.compile(output_file.path)
      vil_data = JSON.parse(File.read(output_file.path))

      # Find the bracket_pair macro (index 0)
      macro0 = vil_data['macro'][0]
      expect(macro0).not_to be_empty

      # Should have tap action
      tap_action = macro0.find { |step| step[0] == 'tap' }
      expect(tap_action).not_to be_nil
      expect(tap_action[1]).to match(/^KC_/)
    end

    it 'compiles text actions correctly' do
      # Create a temporary config with text macro
      temp_config_dir = Dir.mktmpdir
      FileUtils.cp_r("#{config_dir}/.", temp_config_dir)

      # Add a text macro
      text_macro = {
        'name' => 'Text Test',
        'description' => 'Test text macro',
        'enabled' => true,
        'index' => 10,
        'sequence' => [
          { 'action' => 'text', 'content' => 'Hello World' }
        ]
      }
      File.write("#{temp_config_dir}/macros/10_text_test.yaml", YAML.dump(text_macro))

      temp_compiler = described_class.new(temp_config_dir)
      temp_compiler.compile(output_file.path)

      vil_data = JSON.parse(File.read(output_file.path))
      expect(vil_data['macro'][10]).to eq([['text', 'Hello World']])

      FileUtils.rm_rf(temp_config_dir)
    end

    it 'skips disabled macros' do
      # This test verifies that only enabled macros are compiled
      compiler.compile(output_file.path)
      vil_data = JSON.parse(File.read(output_file.path))

      # Count non-empty macros
      non_empty_count = vil_data['macro'].reject(&:empty?).size

      # Count enabled macros in config
      macro_files = Dir.glob("#{config_dir}/macros/*.{yaml,yml}")
      enabled_count = macro_files.count do |file|
        macro_config = YAML.load_file(file)
        macro_config['enabled']
      end

      expect(non_empty_count).to eq(enabled_count)
    end
  end

  describe 'tap dance compilation' do
    it 'compiles tap dance definitions' do
      compiler.compile(output_file.path)
      vil_data = JSON.parse(File.read(output_file.path))

      expect(vil_data['tap_dance']).to be_an(Array)
      expect(vil_data['tap_dance'].size).to eq(32)

      # Each tap dance should have 5 elements [on_tap, on_hold, on_double_tap, on_tap_hold, tapping_term]
      vil_data['tap_dance'].each do |td|
        expect(td.size).to eq(5)
        expect(td[4]).to be_a(Integer) # tapping_term
      end
    end

    it 'places tap dance at correct indices' do
      compiler.compile(output_file.path)
      vil_data = JSON.parse(File.read(output_file.path))

      # Tap dance 0 should exist
      td0 = vil_data['tap_dance'][0]
      expect(td0[0]).not_to eq('KC_NO') # on_tap should be defined
    end

    it 'preserves layer numbers in tap dance actions' do
      compiler.compile(output_file.path)
      vil_data = JSON.parse(File.read(output_file.path))

      # TD 0 has OSL(4) and MO(1)
      td0 = vil_data['tap_dance'][0]
      expect(td0[0]).to eq('OSL(4)')  # on_tap
      expect(td0[1]).to eq('MO(1)')   # on_hold
    end
  end

  describe 'combo compilation' do
    it 'compiles combo definitions' do
      compiler.compile(output_file.path)
      vil_data = JSON.parse(File.read(output_file.path))

      expect(vil_data['combo']).to be_an(Array)
      expect(vil_data['combo'].size).to eq(32)

      # Each combo should have 5 elements [key1, key2, key3, key4, output]
      vil_data['combo'].each do |combo|
        expect(combo.size).to eq(5)
      end
    end

    it 'converts combo trigger keys to QMK format' do
      compiler.compile(output_file.path)
      vil_data = JSON.parse(File.read(output_file.path))

      # Combo 0: D + F → [
      combo0 = vil_data['combo'][0]
      expect(combo0[0]).to eq('KC_D')
      expect(combo0[1]).to eq('KC_F')
      expect(combo0[4]).to eq('KC_LBRACKET')
    end
  end

  describe 'settings compilation' do
    it 'compiles QMK settings correctly' do
      compiler.compile(output_file.path)
      vil_data = JSON.parse(File.read(output_file.path))

      settings = vil_data['settings']
      expect(settings).to be_a(Hash)

      # Check required settings
      expect(settings).to have_key('2')  # combo_timing_window
      expect(settings).to have_key('7')  # tapping_term
      expect(settings).to have_key('18') # tap_code_delay
      expect(settings).to have_key('22') # chordal_hold
    end

    it 'converts boolean chordal_hold to integer' do
      compiler.compile(output_file.path)
      vil_data = JSON.parse(File.read(output_file.path))

      chordal_hold = vil_data['settings']['22']
      expect([0, 1]).to include(chordal_hold)
    end

    it 'uses default settings when settings file is missing' do
      temp_config_dir = Dir.mktmpdir
      FileUtils.cp_r("#{config_dir}/.", temp_config_dir)
      FileUtils.rm_rf("#{temp_config_dir}/settings")

      temp_compiler = described_class.new(temp_config_dir)
      temp_compiler.compile(output_file.path)

      vil_data = JSON.parse(File.read(output_file.path))
      settings = vil_data['settings']

      expect(settings['7']).to eq(250)  # default tapping_term
      expect(settings['2']).to eq(50)   # default combo_timing_window

      FileUtils.rm_rf(temp_config_dir)
    end
  end

  describe 'edge cases' do
    it 'handles empty override layers correctly' do
      compiler.compile(output_file.path)
      vil_data = JSON.parse(File.read(output_file.path))

      # Layers without override files should inherit from base
      layer0 = vil_data['layout'][0]
      # Some higher layers might be empty or have minimal overrides

      vil_data['layout'].each do |layer|
        expect(layer.size).to eq(8)
        layer.each do |row|
          expect(row.size).to eq(7)
        end
      end
    end

    it 'handles KC_NO correctly' do
      compiler.compile(output_file.path)
      vil_data = JSON.parse(File.read(output_file.path))

      # NoKey alias should become KC_NO
      layer1 = vil_data['layout'][1]
      no_key_found = layer1.flatten.include?('KC_NO')
      expect(no_key_found).to be true
    end

    it 'handles special characters in keycodes' do
      compiler.compile(output_file.path)
      vil_data = JSON.parse(File.read(output_file.path))

      # Layer 1 has special chars like "`", "=", etc.
      layer1 = vil_data['layout'][1]

      # These should be converted to KC_* format
      special_chars = layer1.flatten.any? { |k| k.to_s.match?(/^KC_/) }
      expect(special_chars).to be true
    end

    it 'handles multi-argument functions correctly' do
      compiler.compile(output_file.path)
      vil_data = JSON.parse(File.read(output_file.path))

      # LT(1, Space) should become LT(1, KC_SPACE)
      # Check for LT functions with two arguments
      layer0 = vil_data['layout'][0]
      lt_with_args = layer0.flatten.any? { |k| k.to_s.match?(/^LT\d*\(\d+, KC_\w+\)$/) }
      expect(lt_with_args).to be true
    end
  end
