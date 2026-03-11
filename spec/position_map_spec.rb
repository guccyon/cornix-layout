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
        # encoder push should be in normal position (row2, col6)
        # But now returns simple name 'push' instead of 'l_rotary_push'
        result = position_map.symbol_at(:left, 2, 6)
        expect(result).to eq('push')
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
        yaml_data[hand_key].each do |row_key, symbols|
          # Skip thumb_keys as they don't have physical row/col positions
          next if row_key == 'thumb_keys'
          next unless symbols.is_a?(Array)

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

  # === Phase 1拡張: 座標変換メソッドのテスト ===

  describe '#physical_row' do
    it '左手の論理行を物理行に変換' do
      expect(position_map.physical_row(:left, 0)).to eq(0)
      expect(position_map.physical_row(:left, 1)).to eq(1)
      expect(position_map.physical_row(:left, 2)).to eq(2)
      expect(position_map.physical_row(:left, 3)).to eq(3)
    end

    it '右手の論理行を物理行に変換（+4）' do
      expect(position_map.physical_row(:right, 0)).to eq(4)
      expect(position_map.physical_row(:right, 1)).to eq(5)
      expect(position_map.physical_row(:right, 2)).to eq(6)
      expect(position_map.physical_row(:right, 3)).to eq(7)
    end

    it '無効な hand でエラー' do
      expect { position_map.physical_row(:invalid, 0) }.to raise_error(ArgumentError, /Invalid hand/)
    end

    it '無効な logical_row でエラー' do
      expect { position_map.physical_row(:left, 4) }.to raise_error(ArgumentError, /Invalid logical_row/)
      expect { position_map.physical_row(:left, -1) }.to raise_error(ArgumentError, /Invalid logical_row/)
    end
  end

  describe '#physical_col' do
    context '左手' do
      it '論理列をそのまま物理列に変換' do
        expect(position_map.physical_col(:left, 0, 0)).to eq(0)
        expect(position_map.physical_col(:left, 0, 1)).to eq(1)
        expect(position_map.physical_col(:left, 0, 5)).to eq(5)
        expect(position_map.physical_col(:left, 3, 0)).to eq(0)
        expect(position_map.physical_col(:left, 3, 2)).to eq(2)
      end
    end

    context '右手 row0-2（6要素）' do
      it '論理列を物理列に変換（逆順、max=5）' do
        expect(position_map.physical_col(:right, 0, 0)).to eq(5)  # 5 - 0
        expect(position_map.physical_col(:right, 0, 1)).to eq(4)  # 5 - 1
        expect(position_map.physical_col(:right, 0, 5)).to eq(0)  # 5 - 5
        expect(position_map.physical_col(:right, 1, 2)).to eq(3)  # 5 - 2
        expect(position_map.physical_col(:right, 2, 3)).to eq(2)  # 5 - 3
      end
    end

    context '右手 row3（3要素）' do
      it '論理列を物理列に変換（逆順、max=2）' do
        expect(position_map.physical_col(:right, 3, 0)).to eq(2)  # 2 - 0
        expect(position_map.physical_col(:right, 3, 1)).to eq(1)  # 2 - 1
        expect(position_map.physical_col(:right, 3, 2)).to eq(0)  # 2 - 2
      end
    end
  end

  describe '#thumb_physical_row' do
    it '左手親指キーの物理行を返す' do
      expect(position_map.thumb_physical_row(:left)).to eq(3)
    end

    it '右手親指キーの物理行を返す' do
      expect(position_map.thumb_physical_row(:right)).to eq(7)
    end

    it '無効な hand でエラー' do
      expect { position_map.thumb_physical_row(:invalid) }.to raise_error(ArgumentError)
    end
  end

  describe '#thumb_physical_col' do
    context '左手' do
      it '親指キーの物理列を返す（順序通り）' do
        expect(position_map.thumb_physical_col(:left, 0)).to eq(3)  # 3 + 0
        expect(position_map.thumb_physical_col(:left, 1)).to eq(4)  # 3 + 1
        expect(position_map.thumb_physical_col(:left, 2)).to eq(5)  # 3 + 2
      end
    end

    context '右手' do
      it '親指キーの物理列を返す（逆順）' do
        expect(position_map.thumb_physical_col(:right, 0)).to eq(5)  # 5 - 0
        expect(position_map.thumb_physical_col(:right, 1)).to eq(4)  # 5 - 1
        expect(position_map.thumb_physical_col(:right, 2)).to eq(3)  # 5 - 2
      end
    end

    it '無効な thumb_idx でエラー' do
      expect { position_map.thumb_physical_col(:left, 3) }.to raise_error(ArgumentError, /Invalid thumb_idx/)
      expect { position_map.thumb_physical_col(:left, -1) }.to raise_error(ArgumentError, /Invalid thumb_idx/)
    end
  end

  describe '#encoder_push_position' do
    it '左エンコーダープッシュの物理位置を返す' do
      expect(position_map.encoder_push_position(:left)).to eq({ row: 2, col: 6 })
    end

    it '右エンコーダープッシュの物理位置を返す' do
      expect(position_map.encoder_push_position(:right)).to eq({ row: 5, col: 6 })
    end

    it '無効な side でエラー' do
      expect { position_map.encoder_push_position(:invalid) }.to raise_error(ArgumentError, /Invalid side/)
    end
  end
end
