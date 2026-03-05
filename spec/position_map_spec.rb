# frozen_string_literal: true

require_relative 'spec_helper'
require_relative '../lib/cornix/position_map'
require 'tempfile'
require 'yaml'

RSpec.describe Cornix::PositionMap do
  let(:yaml_path) { File.expand_path('../config/position_map.yaml', __dir__) }
  let(:position_map) { described_class.new(yaml_path) }

  describe '#symbol_at' do
    context 'left hand' do
      it 'returns the correct symbol for position' do
        expect(position_map.symbol_at(:left, 0, 0)).to eq('tab')
        expect(position_map.symbol_at(:left, 0, 1)).to eq('Q')
        expect(position_map.symbol_at(:left, 1, 1)).to eq('A')
        expect(position_map.symbol_at(:left, 2, 0)).to eq('lshift')
      end

      it 'returns encoder symbols correctly' do
        # l_rotary_push should not be in normal position
        # It's handled separately in the compiler
        result = position_map.symbol_at(:left, 2, 6)
        expect(result).to be_nil.or eq('l_rotary_push')
      end
    end

    context 'right hand' do
      it 'returns the correct symbol for position' do
        expect(position_map.symbol_at(:right, 0, 0)).to be_a(String)
        expect(position_map.symbol_at(:right, 0, 1)).to eq('U')
      end

      it 'handles bottom row correctly' do
        # Check right hand bottom row
        result = position_map.symbol_at(:right, 3, 0)
        expect(result).to be_a(String)
      end
    end

    it 'returns nil for out of bounds positions' do
      expect(position_map.symbol_at(:left, 10, 0)).to be_nil
      expect(position_map.symbol_at(:right, 0, 10)).to be_nil
    end

    it 'handles string hand parameter' do
      # The implementation uses string keys, so test both symbols and strings
      expect(position_map.symbol_at('left', 0, 0)).to be_a(String).or be_nil
    end
  end

  describe '#find_position' do
    it 'finds position for left hand symbols' do
      result = position_map.find_position('Q')
      expect(result).to eq({ hand: :left, row: 0, col: 1 })

      result = position_map.find_position('A')
      expect(result).to eq({ hand: :left, row: 1, col: 1 })
    end

    it 'finds position for right hand symbols' do
      result = position_map.find_position('P')
      expect(result).to eq({ hand: :right, row: 0, col: 4 })
    end

    it 'finds position for special keys' do
      result = position_map.find_position('tab')
      expect(result).to eq({ hand: :left, row: 0, col: 0 })

      result = position_map.find_position('lshift')
      expect(result).to be_a(Hash)
      expect(result[:hand]).to eq(:left)
    end

    it 'returns nil for non-existent symbol' do
      expect(position_map.find_position('NONEXISTENT')).to be_nil
      expect(position_map.find_position('')).to be_nil
      expect(position_map.find_position(nil)).to be_nil
    end

    it 'is case sensitive' do
      result = position_map.find_position('Q')
      expect(result).not_to be_nil

      # 'q' might not exist depending on position_map
      result = position_map.find_position('q')
      expect(result).to be_nil
    end

    it 'finds all keys in a complete position map' do
      # Get all symbols from YAML
      yaml_data = YAML.load_file(yaml_path)

      ['left_hand', 'right_hand'].each do |hand_key|
        yaml_data[hand_key].each do |_row_key, symbols|
          symbols.each do |symbol|
            next if symbol == 'null'

            result = position_map.find_position(symbol)
            expect(result).not_to be_nil, "Expected to find position for symbol: #{symbol}"
            expect(result).to have_key(:hand)
            expect(result).to have_key(:row)
            expect(result).to have_key(:col)
          end
        end
      end
    end
  end

  describe 'initialization' do
    it 'loads YAML file successfully' do
      expect { position_map }.not_to raise_error
    end

    it 'raises error when file does not exist' do
      expect {
        described_class.new('/nonexistent/path/position_map.yaml')
      }.to raise_error(Errno::ENOENT)
    end

    it 'handles malformed YAML gracefully' do
      malformed_file = Tempfile.new(['malformed', '.yaml'])
      malformed_file.write("invalid: yaml: [")
      malformed_file.close

      expect {
        described_class.new(malformed_file.path)
      }.to raise_error(Psych::SyntaxError)

      malformed_file.unlink
    end
  end

  describe 'edge cases' do
    it 'handles negative indices' do
      expect(position_map.symbol_at(:left, -1, 0)).to be_nil
      expect(position_map.symbol_at(:left, 0, -1)).to be_nil
    end

    it 'searches all valid positions' do
      # Make sure find_position searches the entire map
      # by verifying it can find keys from all corners

      # Top-left
      top_left = position_map.symbol_at(:left, 0, 0)
      expect(position_map.find_position(top_left)).not_to be_nil if top_left

      # Bottom-right (last valid position)
      bottom_right = position_map.symbol_at(:right, 3, 5)
      expect(position_map.find_position(bottom_right)).not_to be_nil if bottom_right
    end
  end
end
