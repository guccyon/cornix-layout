# frozen_string_literal: true

require_relative 'spec_helper'
require_relative '../lib/cornix/file_renamer'
require 'tempfile'
require 'yaml'
require 'fileutils'
require 'json'

RSpec.describe Cornix::FileRenamer do
  let(:config_dir) { Dir.mktmpdir }
  let(:renamer) { described_class.new(config_dir, backup_on_init: false) }

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
      'via_protocol' => 9,
      'layout_options' => 0,
      'vendor_product_id' => '0x1234',
      'matrix' => { 'rows' => 6, 'cols' => 7 }
    }))

    # Create valid position_map.yaml
    position_map_template = File.join(__dir__, '../lib/cornix/position_map.yaml')
    if File.exist?(position_map_template)
      FileUtils.cp(position_map_template, "#{config_dir}/position_map.yaml")
    else
      # Fallback: create minimal valid position_map
      File.write("#{config_dir}/position_map.yaml", YAML.dump({
        'left_hand' => {
          'row0' => ['tab', 'Q', 'W', 'E', 'R', 'T'],
          'row1' => ['caps', 'A', 'S', 'D', 'F', 'G'],
          'row2' => ['lshift', 'Z', 'X', 'C', 'V', 'B'],
          'row3' => ['lctrl', 'command', 'option'],
          'thumb_keys' => ['left', 'middle', 'right']
        },
        'right_hand' => {
          'row0' => ['Y', 'U', 'I', 'O', 'P', 'backspace'],
          'row1' => ['H', 'J', 'K', 'L', 'colon', 'enter'],
          'row2' => ['N', 'M', 'comma', 'dot', 'up', 'rshift'],
          'row3' => ['left', 'down', 'right'],
          'thumb_keys' => ['left', 'middle', 'right']
        },
        'encoders' => {
          'left' => { 'push' => 'push', 'ccw' => 'ccw', 'cw' => 'cw' },
          'right' => { 'push' => 'push', 'ccw' => 'ccw', 'cw' => 'cw' }
        }
      }))
    end

    # Create valid qmk_settings.yaml
    File.write("#{config_dir}/settings/qmk_settings.yaml", YAML.dump({
      'qmk_settings' => {}
    }))

    # Create base layer
    File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
      'index' => 0,
      'name' => 'Base',
      'mapping' => {
        'left_hand' => {
          'row0' => {}, 'row1' => {}, 'row2' => {}, 'row3' => {}, 'thumb_keys' => {}
        },
        'right_hand' => {
          'row0' => {}, 'row1' => {}, 'row2' => {}, 'row3' => {}, 'thumb_keys' => {}
        },
        'encoders' => {
          'left' => { 'cw' => 'KC_VOLU', 'ccw' => 'KC_VOLD', 'push' => 'KC_MUTE' },
          'right' => { 'cw' => 'KC_VOLU', 'ccw' => 'KC_VOLD', 'push' => 'KC_MPLY' }
        }
      }
    }))
  end

  after do
    FileUtils.rm_rf(config_dir)
  end

  describe '#initialize' do
    it 'initializes with valid config directory' do
      expect(renamer.config_dir).to eq(File.expand_path(config_dir))
    end

    it 'raises error for non-existent directory' do
      expect {
        described_class.new('/nonexistent/dir', backup_on_init: false)
      }.to raise_error(ArgumentError, /not found/)
    end

    it 'creates backup on initialization by default' do
      renamer_with_backup = described_class.new(config_dir, backup_on_init: true)
      expect(renamer_with_backup.backup_path).not_to be_nil
      expect(Dir.exist?(renamer_with_backup.backup_path)).to be true
    end
  end

  describe '#extract_index_prefix' do
    it 'extracts index prefix from numbered files' do
      expect(renamer.send(:extract_index_prefix, '03_macro.yml')).to eq('03_')
      expect(renamer.send(:extract_index_prefix, '00_tap_dance.yml')).to eq('00_')
      expect(renamer.send(:extract_index_prefix, '123_layer.yml')).to eq('123_')
    end

    it 'returns nil for files without index prefix' do
      expect(renamer.send(:extract_index_prefix, 'metadata.yaml')).to be_nil
      expect(renamer.send(:extract_index_prefix, 'position_map.yaml')).to be_nil
    end
  end

  describe '#validate_new_basename' do
    it 'validates matching index prefix' do
      expect {
        renamer.send(:validate_new_basename, '03_new_name.yml', '03_')
      }.not_to raise_error
    end

    it 'raises error for mismatched index prefix' do
      expect {
        renamer.send(:validate_new_basename, '04_new_name.yml', '03_')
      }.to raise_error(ArgumentError, /Index prefix mismatch/)
    end

    it 'raises error for unexpected index prefix' do
      expect {
        renamer.send(:validate_new_basename, '03_new_name.yml', nil)
      }.to raise_error(ArgumentError, /Unexpected index prefix/)
    end

    it 'validates absence of index prefix' do
      expect {
        renamer.send(:validate_new_basename, 'metadata.yaml', nil)
      }.not_to raise_error
    end
  end

  describe '#update_yaml_content' do
    let(:yaml_file) { "#{config_dir}/test.yaml" }

    before do
      File.write(yaml_file, YAML.dump({
        'index' => 0,
        'name' => 'Old Name',
        'description' => 'Old Description'
      }))
    end

    it 'updates specified fields' do
      renamer.send(:update_yaml_content, yaml_file, {
        'name' => 'New Name',
        'description' => 'New Description'
      })

      data = YAML.load_file(yaml_file)
      expect(data['name']).to eq('New Name')
      expect(data['description']).to eq('New Description')
      expect(data['index']).to eq(0)
    end

    it 'skips update when updates hash is empty' do
      original_content = File.read(yaml_file)
      renamer.send(:update_yaml_content, yaml_file, {})
      expect(File.read(yaml_file)).to eq(original_content)
    end

    it 'raises error for non-hash YAML' do
      File.write(yaml_file, "just a string")
      expect {
        renamer.send(:update_yaml_content, yaml_file, { 'name' => 'Test' })
      }.to raise_error(/Invalid YAML structure/)
    end
  end

  describe '#rename_file' do
    let(:macro_file) { "#{config_dir}/macros/03_macro.yml" }
    let(:new_basename) { '03_end_of_line.yml' }

    before do
      File.write(macro_file, YAML.dump({
        'index' => 3,
        'name' => 'Macro 3',
        'sequence' => ['KC_LGUI', 'KC_RIGHT']
      }))
    end

    context 'with valid parameters' do
      it 'renames file successfully' do
        result = renamer.rename_file(macro_file, new_basename)

        expect(result[:success]).to be true
        expect(result[:new_path]).to eq("#{config_dir}/macros/#{new_basename}")
        expect(File.exist?(result[:new_path])).to be true
        expect(File.exist?(macro_file)).to be false
      end

      it 'updates YAML content during rename' do
        result = renamer.rename_file(macro_file, new_basename, content_updates: {
          'name' => 'End of Line',
          'description' => 'Jump to end of line'
        })

        expect(result[:success]).to be true
        data = YAML.load_file(result[:new_path])
        expect(data['name']).to eq('End of Line')
        expect(data['description']).to eq('Jump to end of line')
        expect(data['index']).to eq(3)
      end

      it 'handles same source and destination' do
        result = renamer.rename_file(macro_file, '03_macro.yml')
        expect(result[:success]).to be true
        expect(File.exist?(macro_file)).to be true
      end
    end

    context 'with invalid parameters' do
      it 'fails when source file does not exist' do
        result = renamer.rename_file('nonexistent.yml', new_basename)

        expect(result[:success]).to be false
        expect(result[:error]).to match(/File not found/)
      end

      it 'fails when index prefix does not match' do
        result = renamer.rename_file(macro_file, '04_wrong_index.yml')

        expect(result[:success]).to be false
        expect(result[:error]).to match(/Index prefix mismatch/)
      end

      it 'fails when destination file already exists' do
        existing_file = "#{config_dir}/macros/#{new_basename}"
        File.write(existing_file, 'existing content')

        result = renamer.rename_file(macro_file, new_basename)

        expect(result[:success]).to be false
        expect(result[:error]).to match(/already exists/)
      end
    end
  end

  describe '#validate_rename_plan' do
    let(:macro_file) { "#{config_dir}/macros/03_macro.yml" }

    before do
      File.write(macro_file, YAML.dump({
        'index' => 3,
        'name' => 'Macro 3'
      }))
    end

    it 'returns empty errors for valid plan' do
      plan = {
        old_path: macro_file,
        new_basename: '03_new_name.yml',
        content_updates: { 'name' => 'New Name' }
      }

      errors = renamer.send(:validate_rename_plan, plan)
      expect(errors).to be_empty
    end

    it 'returns error for missing old_path' do
      plan = { new_basename: '03_new_name.yml' }

      errors = renamer.send(:validate_rename_plan, plan)
      expect(errors).to include(/Missing 'old_path'/)
    end

    it 'returns error for missing new_basename' do
      plan = { old_path: macro_file }

      errors = renamer.send(:validate_rename_plan, plan)
      expect(errors).to include(/Missing 'new_basename'/)
    end

    it 'returns error for non-existent file' do
      plan = {
        old_path: 'nonexistent.yml',
        new_basename: '03_new_name.yml'
      }

      errors = renamer.send(:validate_rename_plan, plan)
      expect(errors).to include(/File not found/)
    end

    it 'returns error for index mismatch' do
      plan = {
        old_path: macro_file,
        new_basename: '04_wrong_index.yml'
      }

      errors = renamer.send(:validate_rename_plan, plan)
      expect(errors).to include(/Index prefix mismatch/)
    end

    it 'returns error for destination file exists' do
      existing_file = "#{config_dir}/macros/03_existing.yml"
      File.write(existing_file, 'content')

      plan = {
        old_path: macro_file,
        new_basename: '03_existing.yml'
      }

      errors = renamer.send(:validate_rename_plan, plan)
      expect(errors).to include(/already exists/)
    end

    it 'returns error for invalid YAML syntax' do
      File.write(macro_file, "invalid: yaml: content:")

      plan = {
        old_path: macro_file,
        new_basename: '03_new_name.yml'
      }

      errors = renamer.send(:validate_rename_plan, plan)
      expect(errors).to include(/Invalid YAML syntax/)
    end
  end

  describe '#create_backup' do
    it 'creates backup directory with timestamp' do
      timestamp = '20260305_120000'
      backup_dir = renamer.create_backup(timestamp)

      expect(backup_dir).to eq("#{config_dir}.backup_#{timestamp}")
      expect(Dir.exist?(backup_dir)).to be true
    end

    it 'copies all config files to backup' do
      backup_dir = renamer.create_backup

      expect(File.exist?("#{backup_dir}/metadata.yaml")).to be true
      expect(File.exist?("#{backup_dir}/layers/0_base.yaml")).to be true
      expect(Dir.exist?("#{backup_dir}/macros")).to be true
    end

    it 'creates manifest file' do
      backup_dir = renamer.create_backup
      manifest_path = "#{backup_dir}/.backup_manifest.yaml"

      expect(File.exist?(manifest_path)).to be true

      manifest = YAML.load_file(manifest_path)
      expect(manifest['source_dir']).to eq(config_dir)
      expect(manifest['backup_dir']).to eq(backup_dir)
      expect(manifest['files_count']).to be > 0
    end

    it 'raises error if backup directory already exists' do
      timestamp = '20260305_120000'
      backup_dir = "#{config_dir}.backup_#{timestamp}"
      FileUtils.mkdir_p(backup_dir)

      expect {
        renamer.create_backup(timestamp)
      }.to raise_error(/already exists/)
    end
  end

  describe '#rollback' do
    let!(:backup_path) { renamer.create_backup }

    before do
      # Modify config after backup
      File.write("#{config_dir}/modified.yaml", 'modified content')
    end

    it 'restores config from backup' do
      expect(File.exist?("#{config_dir}/modified.yaml")).to be true

      success = renamer.rollback(backup_path)

      expect(success).to be true
      expect(File.exist?("#{config_dir}/modified.yaml")).to be false
    end

    it 'removes manifest file after restore' do
      renamer.rollback(backup_path)

      manifest_path = "#{config_dir}/.backup_manifest.yaml"
      expect(File.exist?(manifest_path)).to be false
    end

    it 'returns false when backup path does not exist' do
      success = renamer.rollback('/nonexistent/backup')
      expect(success).to be false
    end

    it 'returns false when backup_path is nil' do
      success = renamer.rollback(nil)
      expect(success).to be false
    end
  end

  describe '#verify_compilation' do
    it 'succeeds with valid configuration' do
      result = renamer.verify_compilation

      expect(result[:success]).to be true
      expect(result[:error]).to be_nil
    end

    it 'fails with invalid configuration' do
      # Make metadata invalid
      File.write("#{config_dir}/metadata.yaml", "invalid: yaml: content:")

      result = renamer.verify_compilation

      expect(result[:success]).to be false
      expect(result[:error]).not_to be_nil
    end

    it 'cleans up temporary file' do
      renamer.verify_compilation

      temp_files = Dir.glob("#{Dir.tmpdir}/verify_*.vil")
      expect(temp_files).to be_empty
    end
  end

  describe '#cleanup_backup' do
    it 'removes backup directory' do
      backup_dir = renamer.create_backup

      expect(Dir.exist?(backup_dir)).to be true

      success = renamer.cleanup_backup(backup_dir)

      expect(success).to be true
      expect(Dir.exist?(backup_dir)).to be false
    end

    it 'clears backup_path if it matches' do
      backup_dir = renamer.create_backup
      renamer.cleanup_backup(backup_dir)

      expect(renamer.backup_path).to be_nil
    end

    it 'returns false when backup does not exist' do
      success = renamer.cleanup_backup('/nonexistent/backup')
      expect(success).to be false
    end
  end

  describe '#rename_batch', :skip do
    let(:macro1) { "#{config_dir}/macros/03_macro.yml" }
    let(:macro2) { "#{config_dir}/macros/04_macro.yml" }

    before do
      File.write(macro1, YAML.dump({
        'index' => 3,
        'name' => 'Macro 3'
      }))
      File.write(macro2, YAML.dump({
        'index' => 4,
        'name' => 'Macro 4'
      }))
    end

    context 'with valid plans' do
      it 'renames multiple files successfully' do
        plans = [
          {
            old_path: macro1,
            new_basename: '03_select_word.yml',
            content_updates: { 'name' => 'Select Word' }
          },
          {
            old_path: macro2,
            new_basename: '04_copy_word.yml',
            content_updates: { 'name' => 'Copy Word' }
          }
        ]

        result = renamer.rename_batch(plans)

        # Debug output
        unless result[:success]
          puts "\n=== Batch rename failed ==="
          puts "Completed: #{result[:completed].size} files"
          puts "Failed: #{result[:failed].size} files"
          puts "Errors: #{result[:errors].inspect}"
          puts "========================\n"
        end

        expect(result[:success]).to be true
        expect(result[:completed].size).to eq(2)
        expect(result[:failed]).to be_empty

        expect(File.exist?("#{config_dir}/macros/03_select_word.yml")).to be true
        expect(File.exist?("#{config_dir}/macros/04_copy_word.yml")).to be true

        data1 = YAML.load_file("#{config_dir}/macros/03_select_word.yml")
        expect(data1['name']).to eq('Select Word')
      end

      it 'creates backup before renaming' do
        plans = [{
          old_path: macro1,
          new_basename: '03_new_name.yml'
        }]

        result = renamer.rename_batch(plans)

        expect(result[:backup_path]).not_to be_nil
        expect(Dir.exist?(result[:backup_path])).to be true
      end
    end

    context 'with validation errors' do
      it 'rejects all plans if any plan is invalid' do
        plans = [
          {
            old_path: macro1,
            new_basename: '03_valid.yml'
          },
          {
            old_path: 'nonexistent.yml',
            new_basename: '99_invalid.yml'
          }
        ]

        result = renamer.rename_batch(plans)

        expect(result[:success]).to be false
        expect(result[:errors]).not_to be_empty
        expect(result[:failed].size).to eq(2)
        expect(File.exist?(macro1)).to be true  # Original file unchanged
      end
    end

    context 'with runtime errors' do
      it 'rolls back on compilation failure' do
        plans = [{
          old_path: macro1,
          new_basename: '03_renamed.yml'
        }]

        # Break metadata to cause compilation failure
        allow(renamer).to receive(:verify_compilation).and_return({
          success: false,
          error: 'Compilation failed'
        })

        result = renamer.rename_batch(plans)

        expect(result[:success]).to be false
        expect(result[:rollback_completed]).to be true
        expect(File.exist?(macro1)).to be true
      end
    end
  end

  describe 'integration workflow' do
    it 'handles full rename workflow with backup and verification' do
      # Setup
      macro_file = "#{config_dir}/macros/03_macro.yml"
      File.write(macro_file, YAML.dump({
        'index' => 3,
        'name' => 'Macro 3',
        'description' => '',
        'sequence' => [
          { 'action' => 'down', 'keys' => ['LGui'] },
          { 'action' => 'tap', 'keys' => ['Right'] },
          { 'action' => 'up', 'keys' => ['LGui'] }
        ]
      }))

      # Execute rename
      renamer_with_backup = described_class.new(config_dir, backup_on_init: true)
      result = renamer_with_backup.rename_file(
        macro_file,
        '03_end_of_line.yml',
        content_updates: { 'name' => 'End of Line' }
      )

      # Verify
      expect(result[:success]).to be true
      expect(File.exist?("#{config_dir}/macros/03_end_of_line.yml")).to be true

      data = YAML.load_file("#{config_dir}/macros/03_end_of_line.yml")
      expect(data['name']).to eq('End of Line')
      expect(data['index']).to eq(3)

      # Verify backup exists
      expect(renamer_with_backup.backup_path).not_to be_nil
      expect(Dir.exist?(renamer_with_backup.backup_path)).to be true

      # Verify compilation still works
      compilation_result = renamer_with_backup.verify_compilation
      unless compilation_result[:success]
        puts "\n=== Compilation Failed ==="
        puts "Error: #{compilation_result[:error]}"
        if compilation_result[:backtrace]
          puts "Backtrace:"
          puts compilation_result[:backtrace].first(10).join("\n")
        end
        puts "==="
      end
      expect(compilation_result[:success]).to be true
    end
  end

  describe 'layer reference updates' do
    describe '#update_layer_references' do
      it 'updates name-based Macro references in layers' do
        # Create a macro with initial name
        File.write("#{config_dir}/macros/00_test.yaml", YAML.dump({
          'name' => 'OldMacro',
          'index' => 0,
          'enabled' => true
        }))

        # Create a layer using name-based reference
        File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
          'name' => 'Base',
          'mapping' => {
            'LT1' => "Macro('OldMacro')",
            'LT2' => 'Macro(1)',  # index-based
            'RT1' => 'M2'  # legacy
          }
        }))

        # Update references
        updated = renamer.update_layer_references('OldMacro', 'NewMacro', :macro)

        expect(updated.size).to eq(1)
        expect(updated.first).to include('0_base.yaml')

        # Verify only name-based reference was updated
        layer = YAML.load_file("#{config_dir}/layers/0_base.yaml")
        expect(layer['mapping']['LT1']).to eq("Macro('NewMacro')")
        expect(layer['mapping']['LT2']).to eq('Macro(1)')  # unchanged
        expect(layer['mapping']['RT1']).to eq('M2')  # unchanged
      end

      it 'updates name-based TapDance references in layers' do
        File.write("#{config_dir}/tap_dance/00_test.yaml", YAML.dump({
          'name' => 'OldTapDance',
          'index' => 0,
          'enabled' => true
        }))

        File.write("#{config_dir}/layers/1_layer.yaml", YAML.dump({
          'name' => 'Layer 1',
          'mapping' => {
            'LT1' => "TapDance('OldTapDance')"
          }
        }))

        updated = renamer.update_layer_references('OldTapDance', 'NewTapDance', :tap_dance)

        expect(updated.size).to eq(1)

        layer = YAML.load_file("#{config_dir}/layers/1_layer.yaml")
        expect(layer['mapping']['LT1']).to eq("TapDance('NewTapDance')")
      end

      it 'does not update index-based references' do
        File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
          'name' => 'Base',
          'mapping' => {
            'LT1' => 'Macro(0)',
            'LT2' => 'TapDance(5)'
          }
        }))

        updated = renamer.update_layer_references('OldName', 'NewName', :macro)

        expect(updated).to be_empty

        # Verify nothing changed
        layer = YAML.load_file("#{config_dir}/layers/0_base.yaml")
        expect(layer['mapping']['LT1']).to eq('Macro(0)')
        expect(layer['mapping']['LT2']).to eq('TapDance(5)')
      end

      it 'does not update legacy references' do
        File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
          'name' => 'Base',
          'mapping' => {
            'LT1' => 'M0',
            'LT2' => 'TD(2)'
          }
        }))

        updated = renamer.update_layer_references('OldName', 'NewName', :macro)

        expect(updated).to be_empty

        # Verify nothing changed
        layer = YAML.load_file("#{config_dir}/layers/0_base.yaml")
        expect(layer['mapping']['LT1']).to eq('M0')
        expect(layer['mapping']['LT2']).to eq('TD(2)')
      end

      it 'updates multiple layers with same reference' do
        File.write("#{config_dir}/macros/00_test.yaml", YAML.dump({
          'name' => 'SharedMacro',
          'index' => 0,
          'enabled' => true
        }))

        File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
          'name' => 'Base',
          'mapping' => { 'LT1' => "Macro('SharedMacro')" }
        }))

        File.write("#{config_dir}/layers/1_layer.yaml", YAML.dump({
          'name' => 'Layer 1',
          'mapping' => { 'RT1' => "Macro('SharedMacro')" }
        }))

        updated = renamer.update_layer_references('SharedMacro', 'RenamedMacro', :macro)

        expect(updated.size).to eq(2)

        layer0 = YAML.load_file("#{config_dir}/layers/0_base.yaml")
        layer1 = YAML.load_file("#{config_dir}/layers/1_layer.yaml")

        expect(layer0['mapping']['LT1']).to eq("Macro('RenamedMacro')")
        expect(layer1['mapping']['RT1']).to eq("Macro('RenamedMacro')")
      end

      it 'returns empty array when no references match' do
        File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
          'name' => 'Base',
          'mapping' => { 'LT1' => "Macro('OtherMacro')" }
        }))

        updated = renamer.update_layer_references('NonExistent', 'NewName', :macro)

        expect(updated).to be_empty
      end
    end

    describe '#detect_file_type' do
      it 'detects macro files' do
        expect(renamer.detect_file_type("#{config_dir}/macros/00_test.yaml")).to eq(:macro)
      end

      it 'detects tap dance files' do
        expect(renamer.detect_file_type("#{config_dir}/tap_dance/00_test.yaml")).to eq(:tap_dance)
      end

      it 'detects combo files' do
        expect(renamer.detect_file_type("#{config_dir}/combos/00_test.yaml")).to eq(:combo)
      end

      it 'returns nil for layer files' do
        expect(renamer.detect_file_type("#{config_dir}/layers/0_base.yaml")).to be_nil
      end

      it 'returns nil for other files' do
        expect(renamer.detect_file_type("#{config_dir}/metadata.yaml")).to be_nil
      end
    end

    describe 'integration with rename_file' do
      it 'automatically updates layer references when renaming macro with name change' do
        # Create macro
        File.write("#{config_dir}/macros/00_old.yaml", YAML.dump({
          'name' => 'OldMacroName',
          'index' => 0,
          'enabled' => true
        }))

        # Create layer using this macro
        File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
          'name' => 'Base',
          'mapping' => { 'LT1' => "Macro('OldMacroName')" }
        }))

        # Rename with name update
        result = renamer.rename_file(
          "#{config_dir}/macros/00_old.yaml",
          '00_new.yaml',
          content_updates: { 'name' => 'NewMacroName' }
        )

        expect(result[:success]).to be true

        # Verify layer was updated
        layer = YAML.load_file("#{config_dir}/layers/0_base.yaml")
        expect(layer['mapping']['LT1']).to eq("Macro('NewMacroName')")
      end

      it 'does not update layers when name does not change' do
        File.write("#{config_dir}/macros/00_test.yaml", YAML.dump({
          'name' => 'TestMacro',
          'index' => 0,
          'enabled' => true
        }))

        File.write("#{config_dir}/layers/0_base.yaml", YAML.dump({
          'name' => 'Base',
          'mapping' => { 'LT1' => "Macro('TestMacro')" }
        }))

        # Rename file without name change
        result = renamer.rename_file(
          "#{config_dir}/macros/00_test.yaml",
          '00_renamed.yaml'
        )

        expect(result[:success]).to be true

        # Layer reference should be unchanged
        layer = YAML.load_file("#{config_dir}/layers/0_base.yaml")
        expect(layer['mapping']['LT1']).to eq("Macro('TestMacro')")
      end
    end
  end
end
