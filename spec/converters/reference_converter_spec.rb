# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'
require_relative '../../lib/cornix/converters/reference_converter'

RSpec.describe Cornix::Converters::ReferenceConverter do
  let(:temp_dir) { Dir.mktmpdir }
  let(:config_dir) { File.join(temp_dir, 'config') }
  let(:resolver) { described_class.new(config_dir) }

  before do
    # Create config directory structure
    FileUtils.mkdir_p(File.join(config_dir, 'macros'))
    FileUtils.mkdir_p(File.join(config_dir, 'tap_dance'))
    FileUtils.mkdir_p(File.join(config_dir, 'combos'))

    # Create macro files
    File.write(File.join(config_dir, 'macros', '00_macro.yml'), YAML.dump({
      'index' => 0,
      'name' => 'Copy',
      'description' => 'Copy to clipboard'
    }))

    File.write(File.join(config_dir, 'macros', '03_macro.yml'), YAML.dump({
      'index' => 3,
      'name' => 'End of Line',
      'description' => 'Jump to end of line'
    }))

    File.write(File.join(config_dir, 'macros', '05_macro.yml'), YAML.dump({
      'index' => 5,
      'name' => 'Bracket Combo',
      'description' => 'Insert brackets'
    }))

    # Create tap dance files
    File.write(File.join(config_dir, 'tap_dance', '00_tap_dance.yml'), YAML.dump({
      'index' => 0,
      'name' => 'Escape or Layer',
      'description' => 'Tap for Escape, hold for layer'
    }))

    File.write(File.join(config_dir, 'tap_dance', '02_tap_dance.yml'), YAML.dump({
      'index' => 2,
      'name' => 'Shift or Caps',
      'description' => 'Tap for Shift, double tap for Caps Lock'
    }))

    # Create combo files
    File.write(File.join(config_dir, 'combos', '01_combo.yml'), YAML.dump({
      'index' => 1,
      'name' => 'Enter Combo',
      'description' => 'J+K for Enter'
    }))
  end

  after do
    FileUtils.rm_rf(temp_dir)
  end

  describe '#resolve' do
    context 'with Macro references' do
      it 'resolves name-based Macro reference' do
        token = {
          type: :reference,
          function: 'Macro',
          args: [{ type: :string, value: 'End of Line' }]
        }
        expect(resolver.resolve(token)).to eq('M3')
      end

      it 'resolves index-based Macro reference' do
        token = {
          type: :reference,
          function: 'Macro',
          args: [{ type: :number, value: 3 }]
        }
        expect(resolver.resolve(token)).to eq('M3')
      end

      it 'resolves first Macro (index 0)' do
        token = {
          type: :reference,
          function: 'Macro',
          args: [{ type: :string, value: 'Copy' }]
        }
        expect(resolver.resolve(token)).to eq('M0')
      end

      it 'raises error for non-existent Macro name' do
        token = {
          type: :reference,
          function: 'Macro',
          args: [{ type: :string, value: 'NonExistent' }]
        }
        expect { resolver.resolve(token) }.to raise_error(/Macro 'NonExistent' not found/)
      end

      it 'raises error for non-existent Macro index' do
        token = {
          type: :reference,
          function: 'Macro',
          args: [{ type: :number, value: 99 }]
        }
        expect { resolver.resolve(token) }.to raise_error(/Macro index 99 not found/)
      end
    end

    context 'with TapDance references' do
      it 'resolves name-based TapDance reference' do
        token = {
          type: :reference,
          function: 'TapDance',
          args: [{ type: :string, value: 'Escape or Layer' }]
        }
        expect(resolver.resolve(token)).to eq('TD(0)')
      end

      it 'resolves index-based TapDance reference' do
        token = {
          type: :reference,
          function: 'TapDance',
          args: [{ type: :number, value: 2 }]
        }
        expect(resolver.resolve(token)).to eq('TD(2)')
      end

      it 'raises error for non-existent TapDance name' do
        token = {
          type: :reference,
          function: 'TapDance',
          args: [{ type: :string, value: 'Unknown' }]
        }
        expect { resolver.resolve(token) }.to raise_error(/TapDance 'Unknown' not found/)
      end
    end

    context 'with Combo references' do
      it 'resolves name-based Combo reference' do
        token = {
          type: :reference,
          function: 'Combo',
          args: [{ type: :string, value: 'Enter Combo' }]
        }
        expect(resolver.resolve(token)).to eq('COMBO(1)')
      end

      it 'resolves index-based Combo reference' do
        token = {
          type: :reference,
          function: 'Combo',
          args: [{ type: :number, value: 1 }]
        }
        expect(resolver.resolve(token)).to eq('COMBO(1)')
      end
    end

    context 'with invalid tokens' do
      it 'returns nil for non-reference token' do
        token = { type: :alias, value: 'Tab' }
        expect(resolver.resolve(token)).to be_nil
      end

      it 'returns nil for nil token' do
        expect(resolver.resolve(nil)).to be_nil
      end

      it 'raises error for invalid argument type' do
        token = {
          type: :reference,
          function: 'Macro',
          args: [{ type: :unknown, value: 'test' }]
        }
        expect { resolver.resolve(token) }.to raise_error(/Invalid reference argument type/)
      end

      it 'returns nil for unknown function name' do
        token = {
          type: :reference,
          function: 'Unknown',
          args: [{ type: :string, value: 'test' }]
        }
        expect(resolver.resolve(token)).to be_nil
      end
    end
  end

  describe '#reverse_resolve' do
    context 'with prefer_name: true' do
      it 'reverse resolves M0 to name-based Macro' do
        result = resolver.reverse_resolve('M0', prefer_name: true)
        expect(result).to eq({
          type: :reference,
          function: 'Macro',
          args: [{ type: :string, value: 'Copy' }]
        })
      end

      it 'reverse resolves M3 to name-based Macro' do
        result = resolver.reverse_resolve('M3', prefer_name: true)
        expect(result).to eq({
          type: :reference,
          function: 'Macro',
          args: [{ type: :string, value: 'End of Line' }]
        })
      end

      it 'reverse resolves TD(0) to name-based TapDance' do
        result = resolver.reverse_resolve('TD(0)', prefer_name: true)
        expect(result).to eq({
          type: :reference,
          function: 'TapDance',
          args: [{ type: :string, value: 'Escape or Layer' }]
        })
      end

      it 'reverse resolves TD(2) to name-based TapDance' do
        result = resolver.reverse_resolve('TD(2)', prefer_name: true)
        expect(result).to eq({
          type: :reference,
          function: 'TapDance',
          args: [{ type: :string, value: 'Shift or Caps' }]
        })
      end

      it 'falls back to index-based for non-existent macro' do
        result = resolver.reverse_resolve('M99', prefer_name: true)
        expect(result).to eq({
          type: :reference,
          function: 'Macro',
          args: [{ type: :number, value: 99 }]
        })
      end

      it 'falls back to index-based for non-existent tap dance' do
        result = resolver.reverse_resolve('TD(99)', prefer_name: true)
        expect(result).to eq({
          type: :reference,
          function: 'TapDance',
          args: [{ type: :number, value: 99 }]
        })
      end
    end

    context 'with prefer_name: false' do
      it 'reverse resolves M0 to index-based Macro' do
        result = resolver.reverse_resolve('M0', prefer_name: false)
        expect(result).to eq({
          type: :reference,
          function: 'Macro',
          args: [{ type: :number, value: 0 }]
        })
      end

      it 'reverse resolves TD(2) to index-based TapDance' do
        result = resolver.reverse_resolve('TD(2)', prefer_name: false)
        expect(result).to eq({
          type: :reference,
          function: 'TapDance',
          args: [{ type: :number, value: 2 }]
        })
      end
    end

    context 'with non-reference keycodes' do
      it 'returns nil for KC_TAB' do
        expect(resolver.reverse_resolve('KC_TAB')).to be_nil
      end

      it 'returns nil for MO(3)' do
        expect(resolver.reverse_resolve('MO(3)')).to be_nil
      end

      it 'returns nil for regular alias' do
        expect(resolver.reverse_resolve('Tab')).to be_nil
      end
    end
  end

  describe '#validate_reference' do
    context 'with valid references' do
      it 'validates name-based Macro reference' do
        token = {
          type: :reference,
          function: 'Macro',
          args: [{ type: :string, value: 'Copy' }]
        }
        result = resolver.validate_reference(token)
        expect(result[:valid]).to be true
      end

      it 'validates index-based Macro reference' do
        token = {
          type: :reference,
          function: 'Macro',
          args: [{ type: :number, value: 3 }]
        }
        result = resolver.validate_reference(token)
        expect(result[:valid]).to be true
      end

      it 'validates name-based TapDance reference' do
        token = {
          type: :reference,
          function: 'TapDance',
          args: [{ type: :string, value: 'Escape or Layer' }]
        }
        result = resolver.validate_reference(token)
        expect(result[:valid]).to be true
      end

      it 'validates index-based TapDance reference' do
        token = {
          type: :reference,
          function: 'TapDance',
          args: [{ type: :number, value: 2 }]
        }
        result = resolver.validate_reference(token)
        expect(result[:valid]).to be true
      end

      it 'validates Combo reference' do
        token = {
          type: :reference,
          function: 'Combo',
          args: [{ type: :string, value: 'Enter Combo' }]
        }
        result = resolver.validate_reference(token)
        expect(result[:valid]).to be true
      end
    end

    context 'with invalid references' do
      it 'invalidates non-existent Macro name' do
        token = {
          type: :reference,
          function: 'Macro',
          args: [{ type: :string, value: 'NonExistent' }]
        }
        result = resolver.validate_reference(token)
        expect(result[:valid]).to be false
        expect(result[:error]).to match(/not found/)
      end

      it 'invalidates non-existent Macro index (in range)' do
        token = {
          type: :reference,
          function: 'Macro',
          args: [{ type: :number, value: 10 }]
        }
        result = resolver.validate_reference(token)
        expect(result[:valid]).to be false
        expect(result[:error]).to match(/not found/)
      end

      it 'invalidates out-of-range index' do
        token = {
          type: :reference,
          function: 'Macro',
          args: [{ type: :number, value: 100 }]
        }
        result = resolver.validate_reference(token)
        expect(result[:valid]).to be false
        expect(result[:error]).to match(/out of range/)
      end

      it 'invalidates negative index' do
        token = {
          type: :reference,
          function: 'Macro',
          args: [{ type: :number, value: -1 }]
        }
        result = resolver.validate_reference(token)
        expect(result[:valid]).to be false
        expect(result[:error]).to match(/out of range/)
      end

      it 'invalidates unknown function name' do
        token = {
          type: :reference,
          function: 'Unknown',
          args: [{ type: :string, value: 'test' }]
        }
        result = resolver.validate_reference(token)
        expect(result[:valid]).to be false
        expect(result[:error]).to match(/Unknown reference function/)
      end

      it 'invalidates invalid token format' do
        token = { type: :alias, value: 'Tab' }
        result = resolver.validate_reference(token)
        expect(result[:valid]).to be false
        expect(result[:error]).to match(/Invalid token format/)
      end

      it 'invalidates nil token' do
        result = resolver.validate_reference(nil)
        expect(result[:valid]).to be false
        expect(result[:error]).to match(/Invalid token format/)
      end

      it 'invalidates invalid argument type' do
        token = {
          type: :reference,
          function: 'Macro',
          args: [{ type: :unknown, value: 'test' }]
        }
        result = resolver.validate_reference(token)
        expect(result[:valid]).to be false
        expect(result[:error]).to match(/Invalid argument type/)
      end
    end
  end

  describe 'caching behavior' do
    it 'caches loaded metadata' do
      # First call loads from disk
      token1 = {
        type: :reference,
        function: 'Macro',
        args: [{ type: :string, value: 'Copy' }]
      }
      result1 = resolver.resolve(token1)

      # Delete file from disk
      FileUtils.rm(File.join(config_dir, 'macros', '00_macro.yml'))

      # Second call should use cache (still works)
      token2 = {
        type: :reference,
        function: 'Macro',
        args: [{ type: :string, value: 'Copy' }]
      }
      result2 = resolver.resolve(token2)

      expect(result1).to eq('M0')
      expect(result2).to eq('M0')
    end

    it 'clears cache when clear_cache is called' do
      # Load into cache
      token1 = {
        type: :reference,
        function: 'Macro',
        args: [{ type: :string, value: 'Copy' }]
      }
      resolver.resolve(token1)

      # Delete file and clear cache
      FileUtils.rm(File.join(config_dir, 'macros', '00_macro.yml'))
      resolver.clear_cache

      # Should fail now (cache cleared)
      token2 = {
        type: :reference,
        function: 'Macro',
        args: [{ type: :string, value: 'Copy' }]
      }
      expect { resolver.resolve(token2) }.to raise_error(/not found/)
    end
  end

  describe 'edge cases' do
    it 'handles empty config directory' do
      empty_config = File.join(temp_dir, 'empty_config')
      FileUtils.mkdir_p(empty_config)
      empty_resolver = described_class.new(empty_config)

      token = {
        type: :reference,
        function: 'Macro',
        args: [{ type: :string, value: 'Test' }]
      }
      expect { empty_resolver.resolve(token) }.to raise_error(/not found/)
    end

    it 'handles missing subdirectories' do
      partial_config = File.join(temp_dir, 'partial_config')
      FileUtils.mkdir_p(partial_config)
      # Don't create macros/ subdirectory
      partial_resolver = described_class.new(partial_config)

      token = {
        type: :reference,
        function: 'Macro',
        args: [{ type: :string, value: 'Test' }]
      }
      expect { partial_resolver.resolve(token) }.to raise_error(/not found/)
    end

    it 'handles malformed YAML files' do
      malformed_config = File.join(temp_dir, 'malformed_config')
      FileUtils.mkdir_p(File.join(malformed_config, 'macros'))

      # Create valid file
      File.write(File.join(malformed_config, 'macros', '00_valid.yml'), YAML.dump({
        'index' => 0,
        'name' => 'Valid',
        'description' => 'Valid macro'
      }))

      # Create malformed file (missing index/name)
      File.write(File.join(malformed_config, 'macros', '01_invalid.yml'), YAML.dump({
        'description' => 'Invalid macro'
      }))

      malformed_resolver = described_class.new(malformed_config)

      # Should still resolve valid macro
      token = {
        type: :reference,
        function: 'Macro',
        args: [{ type: :string, value: 'Valid' }]
      }
      expect(malformed_resolver.resolve(token)).to eq('M0')
    end

    it 'handles special characters in names' do
      File.write(File.join(config_dir, 'macros', '10_special.yml'), YAML.dump({
        'index' => 10,
        'name' => 'Copy/Paste (Cmd+C)',
        'description' => 'Special chars macro'
      }))

      token = {
        type: :reference,
        function: 'Macro',
        args: [{ type: :string, value: 'Copy/Paste (Cmd+C)' }]
      }
      expect(resolver.resolve(token)).to eq('M10')
    end
  end
end
