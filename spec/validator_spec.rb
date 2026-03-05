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
          'mapping' => { 'A' => 'KC_A' }
        }))

        File.write("#{config_dir}/layers/1_layer.yaml", YAML.dump({
          'name' => 'Layer 1',
          'overrides' => { 'A' => 'KC_B' }
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
          'output' => 'KC_A'
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
          'overrides' => { 'A' => 'MACRO(nonexistent)' }
        }))

        expect(validator.validate).to be false
      end

      it 'detects unknown tap dance references' do
        File.write("#{config_dir}/layers/1_layer.yaml", YAML.dump({
          'name' => 'Layer 1',
          'overrides' => { 'A' => 'TD(nonexistent)' }
        }))

        expect(validator.validate).to be false
      end

      it 'allows valid macro references by name' do
        File.write("#{config_dir}/macros/test.yaml", YAML.dump({
          'name' => 'test',
          'enabled' => true
        }))

        File.write("#{config_dir}/layers/1_layer.yaml", YAML.dump({
          'name' => 'Layer 1',
          'overrides' => { 'A' => 'MACRO(test)' }
        }))

        expect(validator.validate).to be true
      end

      it 'allows valid tap dance references by name' do
        File.write("#{config_dir}/tap_dance/test.yaml", YAML.dump({
          'name' => 'test',
          'enabled' => true
        }))

        File.write("#{config_dir}/layers/1_layer.yaml", YAML.dump({
          'name' => 'Layer 1',
          'overrides' => { 'A' => 'TD(test)' }
        }))

        expect(validator.validate).to be true
      end

      it 'allows macro references by index' do
        File.write("#{config_dir}/layers/1_layer.yaml", YAML.dump({
          'name' => 'Layer 1',
          'overrides' => { 'A' => 'MACRO(0)' }
        }))

        # Index references are allowed even without defined macros
        # (backward compatibility)
        expect(validator.validate).to be true
      end

      it 'allows tap dance references by index' do
        File.write("#{config_dir}/layers/1_layer.yaml", YAML.dump({
          'name' => 'Layer 1',
          'overrides' => { 'A' => 'TD(0)' }
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
end
