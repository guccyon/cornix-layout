# frozen_string_literal: true

require_relative 'spec_helper'
require_relative '../lib/cornix/validator'
require 'tempfile'
require 'yaml'
require 'fileutils'

RSpec.describe Cornix::Validator do
  let(:config_dir) { Dir.mktmpdir }
  let(:validator) { described_class.new(config_dir) }

  before do
    # Create minimal valid structure
    FileUtils.mkdir_p("#{config_dir}/layers")
    FileUtils.mkdir_p("#{config_dir}/macros")
    FileUtils.mkdir_p("#{config_dir}/tap_dance")
    FileUtils.mkdir_p("#{config_dir}/combos")
    FileUtils.mkdir_p("#{config_dir}/settings")

    # Create valid metadata.yaml
    File.write("#{config_dir}/metadata.yaml", YAML.dump({
      'keyboard' => 'cornix',
      'version' => 1,
      'uid' => 12345678901234567890,
      'vial_protocol' => 6,
      'via_protocol' => 9
    }))

    # Create valid position_map.yaml
    File.write("#{config_dir}/position_map.yaml", YAML.dump({
      'left_hand' => {
        'row0' => { 0 => 'LT1', 1 => 'LT2' },
        'row1' => { 0 => 'LH1', 1 => 'LH2' },
        'thumb_keys' => ['l_thumb_left', 'l_thumb_middle', 'l_thumb_right']
      },
      'right_hand' => {
        'row0' => { 0 => 'RT1', 1 => 'RT2' },
        'row1' => { 0 => 'RH1', 1 => 'RH2' },
        'thumb_keys' => ['r_thumb_left', 'r_thumb_middle', 'r_thumb_right']
      }
    }))
  end

  after do
    FileUtils.rm_rf(config_dir)
  end

  describe '#validate' do
    context 'with valid configuration' do
      before do
        # Create valid layer files
        File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
          'name' => 'Base',
          'mapping' => { 'LT1' => 'A', 'LT2' => 'B' }
        }))

        File.write("#{config_dir}/layers/1_layer.yaml", YAML.dump({
          'name' => 'Layer 1',
          'overrides' => { 'LT1' => 'C' }
        }))

        # Create valid macro
        File.write("#{config_dir}/macros/test_macro.yaml", YAML.dump({
          'name' => 'Test Macro',
          'enabled' => true,
          'sequence' => []
        }))

        # Create valid tap dance
        File.write("#{config_dir}/tap_dance/test_td.yaml", YAML.dump({
          'name' => 'Test TD',
          'enabled' => true,
          'actions' => {}
        }))

        # Create valid combo
        File.write("#{config_dir}/combos/test_combo.yaml", YAML.dump({
          'name' => 'Test Combo',
          'enabled' => true,
          'trigger' => [],
          'output' => 'A'
        }))
      end

      it 'passes validation' do
        expect(validator.validate).to be true
      end
    end

    context 'layer validation' do
      it 'detects invalid layer filenames' do
        File.write("#{config_dir}/layers/invalid.yaml", YAML.dump({
          'name' => 'Invalid'
        }))

        expect(validator.validate).to be false
      end

      it 'detects layer indices out of range' do
        File.write("#{config_dir}/layers/10_layer.yaml", YAML.dump({
          'name' => 'Layer 10'
        }))

        expect(validator.validate).to be false
      end

      it 'detects duplicate layer indices' do
        File.write("#{config_dir}/layers/0_first.yaml", YAML.dump({
          'name' => 'First'
        }))

        File.write("#{config_dir}/layers/0_second.yaml", YAML.dump({
          'name' => 'Second'
        }))

        expect(validator.validate).to be false
      end

      it 'allows valid layer indices 0-9' do
        10.times do |i|
          File.write("#{config_dir}/layers/#{i}_layer.yaml", YAML.dump({
            'name' => "Layer #{i}"
          }))
        end

        expect(validator.validate).to be true
      end
    end

    context 'macro validation' do
      it 'detects missing name field' do
        File.write("#{config_dir}/macros/no_name.yaml", YAML.dump({
          'enabled' => true,
          'sequence' => []
        }))

        expect(validator.validate).to be false
      end

      it 'detects duplicate macro names' do
        File.write("#{config_dir}/macros/first.yaml", YAML.dump({
          'name' => 'Duplicate',
          'enabled' => true
        }))

        File.write("#{config_dir}/macros/second.yaml", YAML.dump({
          'name' => 'Duplicate',
          'enabled' => true
        }))

        expect(validator.validate).to be false
      end

      it 'allows unique macro names' do
        File.write("#{config_dir}/macros/first.yaml", YAML.dump({
          'name' => 'First Macro',
          'enabled' => true
        }))

        File.write("#{config_dir}/macros/second.yaml", YAML.dump({
          'name' => 'Second Macro',
          'enabled' => true
        }))

        expect(validator.validate).to be true
      end
    end

    context 'tap dance validation' do
      it 'detects missing name field' do
        File.write("#{config_dir}/tap_dance/no_name.yaml", YAML.dump({
          'enabled' => true,
          'actions' => {}
        }))

        expect(validator.validate).to be false
      end

      it 'detects duplicate tap dance names' do
        File.write("#{config_dir}/tap_dance/first.yaml", YAML.dump({
          'name' => 'Duplicate TD',
          'enabled' => true
        }))

        File.write("#{config_dir}/tap_dance/second.yaml", YAML.dump({
          'name' => 'Duplicate TD',
          'enabled' => true
        }))

        expect(validator.validate).to be false
      end
    end

    context 'combo validation' do
      it 'detects missing name field' do
        File.write("#{config_dir}/combos/no_name.yaml", YAML.dump({
          'enabled' => true,
          'trigger' => [],
          'output' => 'KC_A'
        }))

        expect(validator.validate).to be false
      end

      it 'detects duplicate combo names' do
        File.write("#{config_dir}/combos/first.yaml", YAML.dump({
          'name' => 'Duplicate Combo',
          'enabled' => true
        }))

        File.write("#{config_dir}/combos/second.yaml", YAML.dump({
          'name' => 'Duplicate Combo',
          'enabled' => true
        }))

        expect(validator.validate).to be false
      end
    end

    context 'layer reference validation' do
      before do
        File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
          'name' => 'Base',
          'mapping' => {}
        }))
      end

      it 'detects unknown macro references' do
        File.write("#{config_dir}/layers/1_layer.yaml", YAML.dump({
          'name' => 'Layer 1',
          'overrides' => { 'LT1' => "Macro('nonexistent')" }
        }))

        expect(validator.validate).to be false
      end

      it 'detects unknown tap dance references' do
        File.write("#{config_dir}/layers/1_layer.yaml", YAML.dump({
          'name' => 'Layer 1',
          'overrides' => { 'LT1' => "TapDance('nonexistent')" }
        }))

        expect(validator.validate).to be false
      end

      it 'allows valid macro references by name' do
        File.write("#{config_dir}/macros/test.yaml", YAML.dump({
          'name' => 'test',
          'enabled' => true,
          'index' => 0
        }))

        File.write("#{config_dir}/layers/1_layer.yaml", YAML.dump({
          'name' => 'Layer 1',
          'overrides' => { 'LT1' => "Macro('test')" }
        }))

        expect(validator.validate).to be true
      end

      it 'allows valid tap dance references by name' do
        File.write("#{config_dir}/tap_dance/test.yaml", YAML.dump({
          'name' => 'test',
          'enabled' => true,
          'index' => 0
        }))

        File.write("#{config_dir}/layers/1_layer.yaml", YAML.dump({
          'name' => 'Layer 1',
          'overrides' => { 'LT1' => "TapDance('test')" }
        }))

        expect(validator.validate).to be true
      end

      it 'allows macro references by index' do
        File.write("#{config_dir}/layers/1_layer.yaml", YAML.dump({
          'name' => 'Layer 1',
          'overrides' => { 'LT1' => 'MACRO(0)' }
        }))

        # Index references are allowed even without defined macros
        # (backward compatibility)
        expect(validator.validate).to be true
      end

      it 'allows tap dance references by index' do
        File.write("#{config_dir}/layers/1_layer.yaml", YAML.dump({
          'name' => 'Layer 1',
          'overrides' => { 'LT1' => 'TD(0)' }
        }))

        # Index references are allowed even without defined tap dances
        expect(validator.validate).to be true
      end
    end
  end

  describe 'error reporting' do
    it 'reports multiple errors at once' do
      # Create multiple invalid configurations
      File.write("#{config_dir}/layers/invalid.yaml", YAML.dump({}))
      File.write("#{config_dir}/layers/10_out_of_range.yaml", YAML.dump({}))
      File.write("#{config_dir}/macros/no_name.yaml", YAML.dump({ 'enabled' => true }))

      # Capture output
      output = StringIO.new
      original_stdout = $stdout
      $stdout = output

      validator.validate

      $stdout = original_stdout
      result = output.string

      # Should report multiple errors
      expect(result).to include('Error')
      expect(result.scan(/Error/).size).to be > 1
    end

    it 'shows success message when valid' do
      File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
        'name' => 'Base'
      }))

      output = StringIO.new
      original_stdout = $stdout
      $stdout = output

      validator.validate

      $stdout = original_stdout
      result = output.string

      expect(result).to include('✓')
      expect(result).to include('passed')
    end
  end

  describe 'edge cases' do
    it 'handles empty directories' do
      # Empty config is technically valid (no errors)
      expect(validator.validate).to be true
    end

    it 'handles only layer 0' do
      File.write("#{config_dir}/layers/0_only.yaml", YAML.dump({
        'name' => 'Only Layer'
      }))

      expect(validator.validate).to be true
    end

    it 'handles gaps in layer indices' do
      File.write("#{config_dir}/layers/0_layer.yaml", YAML.dump({
        'name' => 'Layer 0'
      }))

      File.write("#{config_dir}/layers/5_layer.yaml", YAML.dump({
        'name' => 'Layer 5'
      }))

      File.write("#{config_dir}/layers/9_layer.yaml", YAML.dump({
        'name' => 'Layer 9'
      }))

      # Gaps are allowed
      expect(validator.validate).to be true
    end

    it 'handles .yml extension' do
      File.write("#{config_dir}/layers/0_layer.yml", YAML.dump({
        'name' => 'Layer 0'
      }))

      expect(validator.validate).to be true
    end

    it 'handles mixed .yaml and .yml extensions' do
      File.write("#{config_dir}/layers/0_layer.yaml", YAML.dump({
        'name' => 'Layer 0'
      }))

      File.write("#{config_dir}/layers/1_layer.yml", YAML.dump({
        'name' => 'Layer 1'
      }))

      expect(validator.validate).to be true
    end
  end

  # Phase 1: High-priority validations

  describe 'YAML syntax validation' do
    it 'detects invalid YAML syntax' do
      File.write("#{config_dir}/layers/0_bad.yaml", "invalid: yaml: syntax:\n  - bad")

      expect(validator.validate).to be false
    end

    it 'detects unreadable files' do
      file_path = "#{config_dir}/layers/0_test.yaml"
      File.write(file_path, YAML.dump({ 'name' => 'Test' }))
      File.chmod(0000, file_path)

      expect(validator.validate).to be false

      # Cleanup
      File.chmod(0644, file_path)
    end

    it 'passes with valid YAML files' do
      File.write("#{config_dir}/layers/0_valid.yaml", YAML.dump({
        'name' => 'Valid Layer',
        'mapping' => { 'LT1' => 'A' }
      }))

      expect(validator.validate).to be true
    end
  end

  describe 'metadata validation' do
    it 'detects missing metadata.yaml' do
      FileUtils.rm_f("#{config_dir}/metadata.yaml")

      expect(validator.validate).to be false
    end

    it 'detects missing required fields' do
      File.write("#{config_dir}/metadata.yaml", YAML.dump({
        'keyboard' => 'cornix'
        # Missing: version, uid, vial_protocol, via_protocol
      }))

      expect(validator.validate).to be false
    end

    it 'detects invalid vendor_product_id format' do
      File.write("#{config_dir}/metadata.yaml", YAML.dump({
        'keyboard' => 'cornix',
        'version' => 1,
        'uid' => 12345,
        'vial_protocol' => 6,
        'via_protocol' => 9,
        'vendor_product_id' => 'invalid'
      }))

      expect(validator.validate).to be false
    end

    it 'accepts valid vendor_product_id format' do
      File.write("#{config_dir}/metadata.yaml", YAML.dump({
        'keyboard' => 'cornix',
        'version' => 1,
        'uid' => 12345,
        'vial_protocol' => 6,
        'via_protocol' => 9,
        'vendor_product_id' => '0x4653'
      }))

      expect(validator.validate).to be true
    end

    it 'detects invalid matrix configuration' do
      File.write("#{config_dir}/metadata.yaml", YAML.dump({
        'keyboard' => 'cornix',
        'version' => 1,
        'uid' => 12345,
        'vial_protocol' => 6,
        'via_protocol' => 9,
        'matrix' => {
          'rows' => -1,
          'cols' => 'invalid'
        }
      }))

      expect(validator.validate).to be false
    end

    it 'accepts valid matrix configuration' do
      File.write("#{config_dir}/metadata.yaml", YAML.dump({
        'keyboard' => 'cornix',
        'version' => 1,
        'uid' => 12345,
        'vial_protocol' => 6,
        'via_protocol' => 9,
        'matrix' => {
          'rows' => 8,
          'cols' => 7
        }
      }))

      expect(validator.validate).to be true
    end
  end

  describe 'keycode validation' do
    it 'detects invalid keycodes in layers' do
      File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
        'name' => 'Base',
        'mapping' => {
          'LT1' => 'InvalidKeycode',
          'LT2' => 'B'
        }
      }))

      expect(validator.validate).to be false
    end

    it 'accepts valid QMK keycodes' do
      File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
        'name' => 'Base',
        'mapping' => {
          'LT1' => 'KC_A',
          'LT2' => 'KC_TAB'
        }
      }))

      expect(validator.validate).to be true
    end

    it 'accepts valid aliases' do
      File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
        'name' => 'Base',
        'mapping' => {
          'LT1' => 'A',
          'LT2' => 'Tab',
          'RT1' => 'Space'
        }
      }))

      expect(validator.validate).to be true
    end

    it 'accepts function-style keycodes with layer numbers' do
      File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
        'name' => 'Base',
        'mapping' => {
          'LT1' => 'MO(1)',
          'LT2' => 'LT(2, Space)',
          'RT1' => 'TD(0)'
        }
      }))

      expect(validator.validate).to be true
    end

    it 'accepts modifier functions with keycodes' do
      File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
        'name' => 'Base',
        'mapping' => {
          'LT1' => 'LSFT(A)',
          'LT2' => 'LCTL_T(Esc)'
        }
      }))

      expect(validator.validate).to be true
    end

    it 'detects invalid keycodes in function arguments' do
      File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
        'name' => 'Base',
        'mapping' => {
          'LT1' => 'LSFT(InvalidKey)'
        }
      }))

      expect(validator.validate).to be false
    end

    it 'accepts nested function calls' do
      File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
        'name' => 'Base',
        'mapping' => {
          'LT1' => 'LT(1, LSFT(A))'
        }
      }))

      expect(validator.validate).to be true
    end
  end

  describe 'position reference validation' do
    it 'detects unknown position symbols in layers' do
      File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
        'name' => 'Base',
        'mapping' => {
          'UnknownSymbol' => 'A',
          'LT1' => 'B'
        }
      }))

      expect(validator.validate).to be false
    end

    it 'accepts valid position symbols' do
      File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
        'name' => 'Base',
        'mapping' => {
          'LT1' => 'A',
          'LT2' => 'B',
          'RT1' => 'C'
        }
      }))

      expect(validator.validate).to be true
    end

    it 'warns when position_map.yaml is missing' do
      FileUtils.rm_f("#{config_dir}/position_map.yaml")

      File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
        'name' => 'Base',
        'mapping' => { 'LT1' => 'A' }
      }))

      # Capture output to check for warning
      output = StringIO.new
      original_stdout = $stdout
      $stdout = output

      result = validator.validate

      $stdout = original_stdout
      output_text = output.string

      expect(result).to be true  # Should still pass
      expect(output_text).to include('Warning')
      expect(output_text).to include('position_map.yaml')
    end

    it 'detects corrupted position_map.yaml' do
      File.write("#{config_dir}/position_map.yaml", "invalid: yaml: syntax")

      File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
        'name' => 'Base'
      }))

      expect(validator.validate).to be false
    end
  end

  describe 'position map validation' do
    it 'detects duplicate symbols in position_map.yaml' do
      File.write("#{config_dir}/position_map.yaml", YAML.dump({
        'left_hand' => {
          'row0' => ['LT1', 'LT2'],
          'row1' => ['LT1', 'LT3'],  # LT1が重複
          'thumb_keys' => ['l_thumb_left', 'l_thumb_middle', 'l_thumb_right']
        },
        'right_hand' => {
          'row0' => ['RT1', 'RT2'],
          'thumb_keys' => ['r_thumb_left', 'r_thumb_middle', 'r_thumb_right']
        }
      }))

      expect(validator.validate).to be false
    end

    it 'detects duplicate symbols across hands' do
      File.write("#{config_dir}/position_map.yaml", YAML.dump({
        'left_hand' => {
          'row0' => ['KEY1', 'LT2'],
          'thumb_keys' => ['l_thumb_left', 'l_thumb_middle', 'l_thumb_right']
        },
        'right_hand' => {
          'row0' => ['KEY1', 'RT2'],  # KEY1が左手と重複
          'thumb_keys' => ['r_thumb_left', 'r_thumb_middle', 'r_thumb_right']
        }
      }))

      expect(validator.validate).to be false
    end

    it 'accepts position_map.yaml with unique symbols' do
      File.write("#{config_dir}/position_map.yaml", YAML.dump({
        'left_hand' => {
          'row0' => ['LT1', 'LT2'],
          'row1' => ['LH1', 'LH2'],
          'thumb_keys' => ['l_thumb_left', 'l_thumb_middle', 'l_thumb_right']
        },
        'right_hand' => {
          'row0' => ['RT1', 'RT2'],
          'row1' => ['RH1', 'RH2'],
          'thumb_keys' => ['r_thumb_left', 'r_thumb_middle', 'r_thumb_right']
        }
      }))

      expect(validator.validate).to be true
    end

    it 'ignores nil and empty symbols' do
      File.write("#{config_dir}/position_map.yaml", YAML.dump({
        'left_hand' => {
          'row0' => { 0 => 'LT1', 1 => nil, 2 => '', 3 => 'LT2' },
          'thumb_keys' => ['l_thumb_left', 'l_thumb_middle', 'l_thumb_right']
        },
        'right_hand' => {
          'row0' => { 0 => 'RT1', 1 => nil },
          'thumb_keys' => ['r_thumb_left', 'r_thumb_middle', 'r_thumb_right']
        }
      }))

      expect(validator.validate).to be true
    end

    it 'detects invalid symbol characters (quote required symbols)' do
      File.write("#{config_dir}/position_map.yaml", YAML.dump({
        'left_hand' => {
          'row0' => ['LT1', 'LT2'],
          'row1' => ["'", 'LT3'],  # Single quote requires YAML quotes
          'thumb_keys' => ['l_thumb_left', 'l_thumb_middle', 'l_thumb_right']
        },
        'right_hand' => {
          'row0' => ['RT1', 'RT2'],
          'thumb_keys' => ['r_thumb_left', 'r_thumb_middle', 'r_thumb_right']
        }
      }))

      expect(validator.validate).to be false
    end

    it 'accepts valid symbols (alphanumeric, underscore, hyphen)' do
      File.write("#{config_dir}/position_map.yaml", YAML.dump({
        'left_hand' => {
          'row0' => ['LT1', 'key-2', 'key_3'],
          'row1' => ['ABC123', 'test-key', 'test_key'],
          'thumb_keys' => ['l_thumb_left', 'l_thumb_middle', 'l_thumb_right']
        },
        'right_hand' => {
          'row0' => ['RT1', 'RT2'],
          'thumb_keys' => ['r_thumb_left', 'r_thumb_middle', 'r_thumb_right']
        }
      }))

      expect(validator.validate).to be true
    end

    it 'warns when position_map.yaml is missing' do
      FileUtils.rm_f("#{config_dir}/position_map.yaml")

      # Capture output
      output = StringIO.new
      original_stdout = $stdout
      $stdout = output

      result = validator.validate

      $stdout = original_stdout
      output_text = output.string

      expect(result).to be true  # Should still pass
      expect(output_text).to include('Warning')
      expect(output_text).to include('position_map.yaml')
    end
  end

  describe 'KeycodeParser integration' do
    describe 'reference format validation' do
      it 'validates name-based Macro references' do
        File.write("#{config_dir}/macros/test.yaml", YAML.dump({
          'name' => 'TestMacro',
          'enabled' => true,
          'index' => 0
        }))

        File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
          'name' => 'Base',
          'mapping' => {
            'LT1' => "Macro('TestMacro')"
          }
        }))

        expect(validator.validate).to be true
      end

      it 'validates name-based TapDance references' do
        File.write("#{config_dir}/tap_dance/test.yaml", YAML.dump({
          'name' => 'TestTapDance',
          'enabled' => true,
          'index' => 0
        }))

        File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
          'name' => 'Base',
          'mapping' => {
            'LT1' => "TapDance('TestTapDance')"
          }
        }))

        expect(validator.validate).to be true
      end

      it 'validates index-based Macro references' do
        File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
          'name' => 'Base',
          'mapping' => {
            'LT1' => 'Macro(0)',
            'LT2' => 'Macro(15)',
            'RT1' => 'Macro(31)'
          }
        }))

        expect(validator.validate).to be true
      end

      it 'validates index-based TapDance references' do
        File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
          'name' => 'Base',
          'mapping' => {
            'LT1' => 'TapDance(0)',
            'LT2' => 'TapDance(15)',
            'RT1' => 'TapDance(31)'
          }
        }))

        expect(validator.validate).to be true
      end

      it 'detects invalid index out of range' do
        File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
          'name' => 'Base',
          'mapping' => {
            'LT1' => 'Macro(32)'
          }
        }))

        expect(validator.validate).to be false
      end

      it 'detects non-existent name references' do
        File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
          'name' => 'Base',
          'mapping' => {
            'LT1' => "Macro('NonExistent')"
          }
        }))

        expect(validator.validate).to be false
      end

      it 'validates legacy M0 format' do
        File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
          'name' => 'Base',
          'mapping' => {
            'LT1' => 'M0',
            'LT2' => 'M15'
          }
        }))

        expect(validator.validate).to be true
      end

      it 'validates legacy TD(0) format' do
        File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
          'name' => 'Base',
          'mapping' => {
            'LT1' => 'TD(0)',
            'LT2' => 'TD(15)'
          }
        }))

        expect(validator.validate).to be true
      end
    end

    describe 'function parsing' do
      it 'validates nested function calls' do
        File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
          'name' => 'Base',
          'mapping' => {
            'LT1' => 'LT(1, Space)',
            'LT2' => 'LSFT(Tab)',
            'RT1' => 'LCTL_T(Esc)'
          }
        }))

        expect(validator.validate).to be true
      end

      it 'validates layer switching functions with numbers' do
        File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
          'name' => 'Base',
          'mapping' => {
            'LT1' => 'MO(3)',
            'LT2' => 'TO(5)',
            'RT1' => 'OSL(7)'
          }
        }))

        expect(validator.validate).to be true
      end

      it 'detects invalid function arguments' do
        File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
          'name' => 'Base',
          'mapping' => {
            'LT1' => 'LSFT(InvalidAlias)'
          }
        }))

        expect(validator.validate).to be false
      end
    end

    describe 'keycode parsing' do
      it 'validates QMK keycodes with parser' do
        File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
          'name' => 'Base',
          'mapping' => {
            'LT1' => 'KC_A',
            'LT2' => 'KC_TAB',
            'RT1' => 'KC_SPACE'
          }
        }))

        expect(validator.validate).to be true
      end

      it 'validates aliases with parser' do
        File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
          'name' => 'Base',
          'mapping' => {
            'LT1' => 'A',
            'LT2' => 'Tab',
            'RT1' => 'Space',
            'RT2' => 'Esc'
          }
        }))

        expect(validator.validate).to be true
      end

      it 'detects invalid aliases' do
        File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
          'name' => 'Base',
          'mapping' => {
            'LT1' => 'NotAValidAlias'
          }
        }))

        expect(validator.validate).to be false
      end

      it 'validates numbers as layer indices' do
        File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
          'name' => 'Base',
          'mapping' => {
            'LT1' => 1,
            'LT2' => 5
          }
        }))

        expect(validator.validate).to be true
      end
    end
  end

  describe 'reference typo detection and suggestions' do
    before do
      # Create test macros
      FileUtils.mkdir_p("#{config_dir}/macros")
      File.write("#{config_dir}/macros/00_test.yml", YAML.dump({
        'name' => 'Bracket Pair',
        'description' => 'Insert brackets',
        'enabled' => true,
        'index' => 0,
        'sequence' => []
      }))
      File.write("#{config_dir}/macros/01_test.yml", YAML.dump({
        'name' => 'Curly Bracket Pair',
        'description' => 'Insert curly brackets',
        'enabled' => true,
        'index' => 1,
        'sequence' => []
      }))

      # Create test tap dances
      FileUtils.mkdir_p("#{config_dir}/tap_dance")
      File.write("#{config_dir}/tap_dance/00_test.yml", YAML.dump({
        'name' => 'Layer Switch',
        'description' => 'Switch layer',
        'enabled' => true,
        'index' => 0,
        'actions' => {}
      }))
    end

    it 'detects typo in reference function name and suggests correction' do
      File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
        'name' => 'Base',
        'mapping' => {
          'LT1' => "Maacro('Bracket Pair')"  # Typo: Maacro -> Macro
        }
      }))

      output = StringIO.new
      original_stdout = $stdout
      $stdout = output

      result = validator.validate

      $stdout = original_stdout
      output_text = output.string

      expect(result).to be false
      expect(output_text).to include('Invalid reference function')
      expect(output_text).to include('Maacro')
      expect(output_text).to include("Did you mean 'Macro'")
    end

    it 'detects non-existent reference name and suggests similar names' do
      File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
        'name' => 'Base',
        'mapping' => {
          'LT1' => "Macro('Bracket Pir')"  # Typo: Pir -> Pair
        }
      }))

      output = StringIO.new
      original_stdout = $stdout
      $stdout = output

      result = validator.validate

      $stdout = original_stdout
      output_text = output.string

      expect(result).to be false
      expect(output_text).to include('not found')
      expect(output_text).to include("Did you mean")
      expect(output_text).to include('Bracket Pair')
    end

    it 'suggests multiple similar names when available' do
      File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
        'name' => 'Base',
        'mapping' => {
          'LT1' => "Macro('Bracket')"  # Similar to both "Bracket Pair" and "Curly Bracket Pair"
        }
      }))

      output = StringIO.new
      original_stdout = $stdout
      $stdout = output

      result = validator.validate

      $stdout = original_stdout
      output_text = output.string

      expect(result).to be false
      expect(output_text).to include('not found')
      expect(output_text).to include("Did you mean")
      # Should suggest at least one similar name
      expect(output_text).to match(/Bracket Pair|Curly Bracket Pair/)
    end

    it 'detects typo "TapDannce"' do
      File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
        'name' => 'Base',
        'mapping' => {
          'LT1' => "TapDannce('Layer Switch')"  # Typo: TapDannce -> TapDance
        }
      }))

      output = StringIO.new
      original_stdout = $stdout
      $stdout = output

      result = validator.validate

      $stdout = original_stdout
      output_text = output.string

      expect(result).to be false
      expect(output_text).to include('Invalid reference function')
      expect(output_text).to include('TapDannce')
      expect(output_text).to include("Did you mean 'TapDance'")
    end

    it 'detects completely non-existent macro name without similar names' do
      File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
        'name' => 'Base',
        'mapping' => {
          'LT1' => "Macro('Xyz123')"  # Completely different name
        }
      }))

      output = StringIO.new
      original_stdout = $stdout
      $stdout = output

      result = validator.validate

      $stdout = original_stdout
      output_text = output.string

      expect(result).to be false
      expect(output_text).to include('not found')
      # Should not suggest anything if no similar names
      # (or might suggest something if distance is within threshold)
    end

    it 'accepts valid reference with correct name' do
      File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
        'name' => 'Base',
        'mapping' => {
          'LT1' => "Macro('Bracket Pair')",
          'LT2' => "TapDance('Layer Switch')"
        }
      }))

      expect(validator.validate).to be true
    end

    it 'accepts encoder symbols from position_map.yaml' do
      # Add encoders to position_map
      position_map = YAML.load_file("#{config_dir}/position_map.yaml")
      position_map['encoders'] = {
        'left' => {
          'push' => 'l_rotary_push',
          'ccw' => 'l_rotary_ccw',
          'cw' => 'l_rotary_cw'
        },
        'right' => {
          'push' => 'r_rotary_push',
          'ccw' => 'r_rotary_ccw',
          'cw' => 'r_rotary_cw'
        }
      }
      File.write("#{config_dir}/position_map.yaml", YAML.dump(position_map))

      # Use encoder symbols in layer
      File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
        'name' => 'Base',
        'mapping' => {
          'LT1' => 'A',
          'l_rotary_push' => 'Enter',
          'l_rotary_ccw' => 'KC_VOLU',
          'l_rotary_cw' => 'KC_VOLD',
          'r_rotary_push' => 'Space',
          'r_rotary_ccw' => 'KC_PGUP',
          'r_rotary_cw' => 'KC_PGDN'
        }
      }))

      expect(validator.validate).to be true
    end
  end

  describe 'modifier expression validation' do
    it 'accepts valid simple modifier expression' do
      File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
        'name' => 'Base',
        'mapping' => {
          'LT1' => 'Cmd + Q'
        }
      }))

      expect(validator.validate).to be true
    end

    it 'accepts valid two modifier expression' do
      File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
        'name' => 'Base',
        'mapping' => {
          'LT1' => 'Shift + Cmd + Q'
        }
      }))

      expect(validator.validate).to be true
    end

    it 'accepts valid three modifier expression (MEH)' do
      File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
        'name' => 'Base',
        'mapping' => {
          'LT1' => 'Ctrl + Shift + Alt + Q'
        }
      }))

      expect(validator.validate).to be true
    end

    it 'accepts modifier aliases' do
      File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
        'name' => 'Base',
        'mapping' => {
          'LT1' => 'Command + Q'
        }
      }))

      expect(validator.validate).to be true
    end

    it 'accepts right-side modifiers' do
      File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
        'name' => 'Base',
        'mapping' => {
          'LT1' => 'RShift + Q'
        }
      }))

      expect(validator.validate).to be true
    end

    it 'rejects invalid modifier name' do
      File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
        'name' => 'Base',
        'mapping' => {
          'LT1' => 'InvalidMod + Q'
        }
      }))

      expect(validator.validate).to be false
    end

    it 'accepts key aliases in modifier expressions' do
      File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
        'name' => 'Base',
        'mapping' => {
          'LT1' => 'Cmd + Space'
        }
      }))

      expect(validator.validate).to be true
    end

    it 'accepts KC_ prefixed keys in modifier expressions' do
      File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
        'name' => 'Base',
        'mapping' => {
          'LT1' => 'Cmd + KC_ENTER'
        }
      }))

      expect(validator.validate).to be true
    end
  end
end
