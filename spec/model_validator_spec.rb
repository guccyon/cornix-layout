# frozen_string_literal: true

require_relative '../lib/cornix/model_validator'
require 'tempfile'
require 'yaml'
require 'fileutils'

RSpec.describe Cornix::ModelValidator do
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
      'vendor_product_id' => '0x1234',
      'vial_protocol' => 6,
      'via_protocol' => 9
    }))

    # Create valid position_map.yaml with hierarchical structure
    File.write("#{config_dir}/position_map.yaml", YAML.dump({
      'left_hand' => {
        'row0' => ['LT1', 'LT2'],
        'row1' => ['LH1', 'LH2'],
        'row2' => [],
        'row3' => [],
        'thumb_keys' => ['left', 'middle', 'right']
      },
      'right_hand' => {
        'row0' => ['RT1', 'RT2'],
        'row1' => ['RH1', 'RH2'],
        'row2' => [],
        'row3' => [],
        'thumb_keys' => ['left', 'middle', 'right']
      },
      'encoders' => {
        'left' => { 'push' => 'push', 'ccw' => 'ccw', 'cw' => 'cw' },
        'right' => { 'push' => 'push', 'ccw' => 'ccw', 'cw' => 'cw' }
      }
    }))

    # Create valid settings file
    File.write("#{config_dir}/settings/qmk_settings.yaml", YAML.dump({}))
  end

  after do
    FileUtils.rm_rf(config_dir)
  end

  # Helper to create hierarchical mapping structure
  def hierarchical_mapping(flat_mapping)
    hierarchical = {
      'left_hand' => { 'row0' => {}, 'row1' => {}, 'row2' => {}, 'row3' => {}, 'thumb_keys' => {} },
      'right_hand' => { 'row0' => {}, 'row1' => {}, 'row2' => {}, 'row3' => {}, 'thumb_keys' => {} },
      'encoders' => { 'left' => {}, 'right' => {} }
    }

    flat_mapping.each do |key, value|
      if key.include?('rotary')
        if key.start_with?('l_rotary')
          action = key.sub('l_rotary_', '')
          hierarchical['encoders']['left'][action] = value
        elsif key.start_with?('r_rotary')
          action = key.sub('r_rotary_', '')
          hierarchical['encoders']['right'][action] = value
        end
      elsif key.include?('thumb')
        if key.start_with?('l_thumb')
          hierarchical['left_hand']['thumb_keys'][key] = value
        elsif key.start_with?('r_thumb')
          hierarchical['right_hand']['thumb_keys'][key] = value
        end
      elsif key.start_with?('RT', 'RH', 'r_')
        hierarchical['right_hand']['row0'][key] = value
      else
        hierarchical['left_hand']['row0'][key] = value
      end
    end

    hierarchical
  end

  describe '#validate' do
    context 'with valid configuration' do
      before do
        File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
          'name' => 'Base',
          'description' => 'Base layer',
          'index' => 0,
          'mapping' => hierarchical_mapping({ 'LT1' => 'A', 'LT2' => 'B' })
        }))

        File.write("#{config_dir}/layers/1_second.yaml", YAML.dump({
          'name' => 'Second',
          'description' => 'Second layer',
          'index' => 1,
          'mapping' => hierarchical_mapping({ 'LT1' => 'C' })
        }))
      end

      it 'passes validation' do
        expect(validator.validate).to be true
      end
    end

    context 'file system validation' do
      describe 'layer validation' do
        it 'detects invalid layer filenames' do
          File.write("#{config_dir}/layers/invalid_name.yaml", YAML.dump({
            'name' => 'Layer',
            'description' => 'Test',
            'index' => 0,
            'mapping' => hierarchical_mapping({})
          }))

          validator.validate
          warnings = validator.instance_variable_get(:@warnings)
          expect(warnings.any? { |w| w.include?('Layer filename does not start with index') }).to be true
        end

        it 'detects layer indices out of range' do
          File.write("#{config_dir}/layers/10_invalid.yaml", YAML.dump({
            'name' => 'Invalid',
            'description' => 'Test',
            'index' => 10,
            'mapping' => hierarchical_mapping({})
          }))

          expect(validator.validate).to be false
          expect(validator.instance_variable_get(:@errors).join).to include('out of range')
        end

        it 'detects duplicate layer indices' do
          File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
            'name' => 'Base',
            'description' => 'Test',
            'index' => 0,
            'mapping' => hierarchical_mapping({})
          }))
          File.write("#{config_dir}/layers/0_duplicate.yaml", YAML.dump({
            'name' => 'Duplicate',
            'description' => 'Test',
            'index' => 0,
            'mapping' => hierarchical_mapping({})
          }))

          expect(validator.validate).to be false
          expect(validator.instance_variable_get(:@errors).join).to include('Duplicate')
        end

        it 'allows valid layer indices 0-9' do
          (0..9).each do |i|
            File.write("#{config_dir}/layers/#{i}_layer.yaml", YAML.dump({
              'name' => "Layer #{i}",
              'description' => 'Test',
              'index' => i,
              'mapping' => hierarchical_mapping({})
            }))
          end

          expect(validator.validate).to be true
        end
      end

      describe 'macro validation' do
        it 'detects duplicate macro names' do
          File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
            'name' => 'Base',
            'description' => 'Test',
            'index' => 0,
            'mapping' => hierarchical_mapping({})
          }))
          File.write("#{config_dir}/macros/00_test.yaml", YAML.dump({
            'name' => 'test',
            'index' => 0,
            'sequence' => ['A']
          }))
          File.write("#{config_dir}/macros/01_test.yaml", YAML.dump({
            'name' => 'test',
            'index' => 1,
            'sequence' => ['B']
          }))

          expect(validator.validate).to be false
          expect(validator.instance_variable_get(:@errors).join).to include('Duplicate')
        end

        it 'allows unique macro names' do
          File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
            'name' => 'Base',
            'description' => 'Test',
            'index' => 0,
            'mapping' => hierarchical_mapping({})
          }))
          File.write("#{config_dir}/macros/00_test1.yaml", YAML.dump({
            'name' => 'test1',
            'index' => 0,
            'description' => '',
            'sequence' => [{ 'action' => 'tap', 'keys' => ['A'] }]
          }))
          File.write("#{config_dir}/macros/01_test2.yaml", YAML.dump({
            'name' => 'test2',
            'index' => 1,
            'description' => '',
            'sequence' => [{ 'action' => 'tap', 'keys' => ['B'] }]
          }))

          expect(validator.validate).to be true
        end
      end

      describe 'tap dance validation' do
        it 'detects duplicate tap dance names' do
          File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
            'name' => 'Base',
            'description' => 'Test',
            'index' => 0,
            'mapping' => hierarchical_mapping({})
          }))
          File.write("#{config_dir}/tap_dance/00_test.yaml", YAML.dump({
            'name' => 'test',
            'index' => 0,
            'on_tap' => 'A',
            'on_hold' => 'B',
            'on_double_tap' => 'C',
            'on_tap_hold' => 'D',
            'tapping_term' => 200
          }))
          File.write("#{config_dir}/tap_dance/01_test.yaml", YAML.dump({
            'name' => 'test',
            'index' => 1,
            'on_tap' => 'E',
            'on_hold' => 'F',
            'on_double_tap' => 'G',
            'on_tap_hold' => 'H',
            'tapping_term' => 200
          }))

          expect(validator.validate).to be false
          expect(validator.instance_variable_get(:@errors).join).to include('Duplicate')
        end
      end

      describe 'combo validation' do
        it 'detects duplicate combo names' do
          File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
            'name' => 'Base',
            'description' => 'Test',
            'index' => 0,
            'mapping' => hierarchical_mapping({})
          }))
          File.write("#{config_dir}/combos/00_test.yaml", YAML.dump({
            'name' => 'test',
            'index' => 0,
            'trigger' => ['A', 'B'],
            'output' => 'C'
          }))
          File.write("#{config_dir}/combos/01_test.yaml", YAML.dump({
            'name' => 'test',
            'index' => 1,
            'trigger' => ['D', 'E'],
            'output' => 'F'
          }))

          expect(validator.validate).to be false
          expect(validator.instance_variable_get(:@errors).join).to include('Duplicate')
        end
      end
    end

    describe 'YAML syntax validation' do
      it 'detects invalid YAML syntax' do
        File.write("#{config_dir}/layers/0_base.yaml", "invalid: yaml: syntax: [")

        expect(validator.validate).to be false
        expect(validator.instance_variable_get(:@errors).join).to include('YAML syntax error')
      end

      it 'passes with valid YAML files' do
        File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
          'name' => 'Base',
          'description' => 'Test',
          'index' => 0,
          'mapping' => hierarchical_mapping({})
        }))

        expect(validator.validate).to be true
      end
    end

    describe 'model validation delegation' do
      it 'delegates to VialConfig validation' do
        # Create valid layer file
        File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
          'name' => 'Base',
          'description' => 'Test',
          'index' => 0,
          'mapping' => hierarchical_mapping({})
        }))

        # Validation should succeed
        expect(validator.validate).to be true
      end

      it 'reports model validation errors' do
        # Create layer with missing required field (name is blank)
        File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
          'name' => '',  # Invalid: blank name
          'description' => 'Test',
          'index' => 0,
          'mapping' => hierarchical_mapping({})
        }))

        expect(validator.validate).to be false
        expect(validator.instance_variable_get(:@errors).join).to include('cannot be blank')
      end
    end

    describe 'error reporting' do
      it 'reports multiple errors at once' do
        # Create multiple files with duplicate indices
        File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
          'name' => 'Base',
          'description' => 'Test',
          'index' => 0,
          'mapping' => hierarchical_mapping({})
        }))
        File.write("#{config_dir}/layers/0_duplicate.yaml", YAML.dump({
          'name' => 'Duplicate',
          'description' => 'Test',
          'index' => 0,  # Duplicate index
          'mapping' => hierarchical_mapping({})
        }))
        File.write("#{config_dir}/layers/1_first.yaml", YAML.dump({
          'name' => 'First',
          'description' => 'Test',
          'index' => 1,
          'mapping' => hierarchical_mapping({})
        }))
        File.write("#{config_dir}/layers/1_duplicate2.yaml", YAML.dump({
          'name' => 'Second Duplicate',
          'description' => 'Test',
          'index' => 1,  # Another duplicate
          'mapping' => hierarchical_mapping({})
        }))

        expect(validator.validate).to be false
        errors = validator.instance_variable_get(:@errors)
        expect(errors.size).to be >= 2
      end

      it 'エラーメッセージにYAMLファイル名が含まれる' do
        # 無効なmacroファイルを作成
        File.write("#{config_dir}/macros/10_invalid_macro.yaml", YAML.dump({
          'name' => 'Invalid Macro',
          'description' => 'Test',
          'index' => 10,
          'sequence' => [
            { 'action' => 'tap', 'keys' => ['InvalidKeyCode123'] }
          ]
        }))
        # Layer 0を作成（必須）
        File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
          'name' => 'Base',
          'description' => 'Test',
          'index' => 0,
          'mapping' => hierarchical_mapping({})
        }))

        expect(validator.validate).to be false
        errors = validator.instance_variable_get(:@errors)
        error_message = errors.join("\n")
        expect(error_message).to include('10_invalid_macro.yaml')
      end

      it 'エラーメッセージにフィールドパスが含まれる' do
        # 無効なsequenceを持つmacroファイルを作成
        File.write("#{config_dir}/macros/20_bad_sequence.yaml", YAML.dump({
          'name' => 'Bad Sequence',
          'description' => 'Test',
          'index' => 20,
          'sequence' => [
            { 'action' => 'tap', 'keys' => ['A', 'BadKey', 'C'] }
          ]
        }))
        # Layer 0を作成（必須）
        File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
          'name' => 'Base',
          'description' => 'Test',
          'index' => 0,
          'mapping' => hierarchical_mapping({})
        }))

        expect(validator.validate).to be false
        errors = validator.instance_variable_get(:@errors)
        error_message = errors.join("\n")
        # sequence[0].keys[1] のようなフィールドパスが含まれることを期待
        expect(error_message).to include('sequence')
        expect(error_message).to include('BadKey')
      end

      it 'shows success message when valid' do
        File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
          'name' => 'Base',
          'description' => 'Test',
          'index' => 0,
          'mapping' => hierarchical_mapping({})
        }))

        result = validator.validate
        expect(result).to be true
      end
    end

    describe 'edge cases' do
      it 'handles only layer 0' do
        File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
          'name' => 'Base',
          'description' => 'Test',
          'index' => 0,
          'mapping' => hierarchical_mapping({})
        }))

        expect(validator.validate).to be true
      end

      it 'handles gaps in layer indices' do
        File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
          'name' => 'Base',
          'description' => 'Test',
          'index' => 0,
          'mapping' => hierarchical_mapping({})
        }))
        File.write("#{config_dir}/layers/5_layer.yaml", YAML.dump({
          'name' => 'Layer 5',
          'description' => 'Test',
          'index' => 5,
          'mapping' => hierarchical_mapping({})
        }))

        expect(validator.validate).to be true
      end

      it 'handles .yml extension' do
        File.write("#{config_dir}/layers/0_base.yml", YAML.dump({
          'name' => 'Base',
          'description' => 'Test',
          'index' => 0,
          'mapping' => hierarchical_mapping({})
        }))

        expect(validator.validate).to be true
      end

      it 'handles mixed .yaml and .yml extensions' do
        File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
          'name' => 'Base',
          'description' => 'Test',
          'index' => 0,
          'mapping' => hierarchical_mapping({})
        }))
        File.write("#{config_dir}/layers/1_second.yml", YAML.dump({
          'name' => 'Second',
          'description' => 'Test',
          'index' => 1,
          'mapping' => hierarchical_mapping({})
        }))

        expect(validator.validate).to be true
      end
    end
  end
end
