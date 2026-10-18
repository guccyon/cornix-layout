# frozen_string_literal: true

require 'spec_helper'
require_relative 'support/domain_factories'

RSpec.describe Cornix::Domain::PositionMap do
  include DomainFactories

  subject(:map) { described_class.from_h(position_map_hash) }

  # layout.vil の layout[row][col] に入るキー（.claude/architecture/coordinate_system.md の物理配列）
  # [手, グループ, シンボル]。:push はエンコーダのプッシュ、nil はキーがない位置（-1）
  let(:physical_layout) do
    l = ->(g, s) { ['left_hand', g, s] }
    r = ->(g, s) { ['right_hand', g, s] }
    [
      [l['row0', 'tab'], l['row0', 'Q'], l['row0', 'W'], l['row0', 'E'], l['row0', 'R'], l['row0', 'T'], nil],
      [l['row1', 'caps'], l['row1', 'A'], l['row1', 'S'], l['row1', 'D'], l['row1', 'F'], l['row1', 'G'], nil],
      [l['row2', 'lshift'], l['row2', 'Z'], l['row2', 'X'], l['row2', 'C'], l['row2', 'V'], l['row2', 'B'], :push],
      [l['row3', 'lctrl'], l['row3', 'command'], l['row3', 'option'],
       l['thumb_keys', 'left'], l['thumb_keys', 'middle'], l['thumb_keys', 'right'], nil],
      [r['row0', 'backspace'], r['row0', 'P'], r['row0', 'O'], r['row0', 'I'], r['row0', 'U'], r['row0', 'Y'], nil],
      [r['row1', 'enter'], r['row1', 'colon'], r['row1', 'L'], r['row1', 'K'], r['row1', 'J'], r['row1', 'H'], :push],
      [r['row2', 'rshift'], r['row2', 'up'], r['row2', 'dot'], r['row2', 'comma'], r['row2', 'M'], r['row2', 'N'], nil],
      [r['row3', 'right'], r['row3', 'down'], r['row3', 'left'],
       r['thumb_keys', 'right'], r['thumb_keys', 'middle'], r['thumb_keys', 'left'], nil]
    ]
  end

  describe '物理座標（layout.vil の 8 行 × 7 列）' do
    it 'すべてのシンボルが既定の配列の位置に対応する' do
      physical_layout.each_with_index do |cols, row|
        cols.each_with_index do |entry, col|
          next unless entry.is_a?(Array)

          pos = map.position(*entry)
          expect(pos).not_to be_nil, entry.join('.')
          expect(map.matrix(pos)).to eq([row, col]), entry.join('.')
          expect(map.position_at(row, col)).to eq(pos)
        end
      end
    end

    it 'キーがない位置とエンコーダのプッシュ、範囲外は position_at が nil' do
      physical_layout.each_with_index do |cols, row|
        cols.each_with_index do |entry, col|
          expect(map.position_at(row, col)).to be_nil unless entry.is_a?(Array)
        end
      end
      expect(map.position_at(8, 0)).to be_nil
      expect(map.position_at(0, 7)).to be_nil
      expect(map.position_at(-1, 0)).to be_nil
    end

    it '論理座標の規則（左手はそのまま、右手は行 +4・列を反転、親指は row 3 / 7 の col 3〜5）' do
      expect(map.matrix(key_position(:left, 1, 2))).to eq([1, 2])
      expect(map.matrix(key_position(:left, 3, 0))).to eq([3, 0])
      expect(map.matrix(key_position(:left, 3, 4))).to eq([3, 4])
      expect(map.matrix(key_position(:right, 0, 0))).to eq([4, 5])
      expect(map.matrix(key_position(:right, 0, 5))).to eq([4, 0])
      expect(map.matrix(key_position(:right, 3, 0))).to eq([7, 2])
      expect(map.matrix(key_position(:right, 3, 2))).to eq([7, 0])
      expect(map.matrix(key_position(:right, 3, 3))).to eq([7, 5])
      expect(map.matrix(key_position(:right, 3, 5))).to eq([7, 3])
    end

    it 'エンコーダのプッシュは左 (2, 6)、右 (5, 6)' do
      expect(map.encoder_push_matrix(:left)).to eq([2, 6])
      expect(map.encoder_push_matrix(:right)).to eq([5, 6])
      expect { map.encoder_push_matrix(:center) }.to raise_error(Cornix::InvalidValue)
    end

    it '定数でマトリクスの大きさを持つ' do
      expect([described_class::MATRIX_ROWS, described_class::MATRIX_COLS]).to eq([8, 7])
    end
  end

  describe '#position / #symbol / #path' do
    it '手・グループ・シンボルで位置を引き、位置からシンボルを引く' do
      pos = map.position('left_hand', 'row0', 'tab')
      expect(pos).to eq(key_position(:left, 0, 0))
      expect(map.symbol(pos)).to eq(%w[row0 tab])
      expect(map.hand_key(pos)).to eq('left_hand')
      expect(map.path(pos)).to eq('left_hand.row0.tab')
    end

    it '親指キーは thumb_keys グループで row 3 の col 3〜5' do
      expect(map.position('left_hand', 'thumb_keys', 'left')).to eq(key_position(:left, 3, 3))
      expect(map.position('right_hand', 'thumb_keys', 'right')).to eq(key_position(:right, 3, 5))
      expect(map.path(key_position(:right, 3, 4))).to eq('right_hand.thumb_keys.middle')
    end

    it 'グループが違えば同じシンボルを区別する' do
      expect(map.position('right_hand', 'row3', 'left')).to eq(key_position(:right, 3, 0))
      expect(map.position('right_hand', 'thumb_keys', 'left')).to eq(key_position(:right, 3, 3))
    end

    it 'ないものは nil' do
      expect(map.position('left_hand', 'row0', 'Y')).to be_nil
      expect(map.position('left_hand', 'row9', 'tab')).to be_nil
      expect(map.position('encoders', 'left', 'push')).to be_nil
    end

    it 'シンボルは文字列でも記号でも引ける' do
      expect(map.position(:left_hand, :row0, :Q)).to eq(key_position(:left, 0, 1))
    end
  end

  describe '#positions' do
    it '左手 row0〜row3・親指、右手の順に 48 か所' do
      expect(map.positions.size).to eq(48)
      expect(map.positions.first).to eq(key_position(:left, 0, 0))
      expect(map.positions[21..23]).to eq([key_position(:left, 3, 3), key_position(:left, 3, 4), key_position(:left, 3, 5)])
      expect(map.positions[24]).to eq(key_position(:right, 0, 0))
      expect(map.positions.uniq.size).to eq(48)
      expect(map.positions).to be_frozen
    end
  end

  describe 'カスタマイズした position_map' do
    # authors-keymap の config/position_map.yaml と同じ名前の付け替え
    let(:hash) do
      position_map_hash.tap do |h|
        h['left_hand']['row1'] = %w[lctrl A S D F G]
        h['left_hand']['row3'] = %w[caps fn option]
      end
    end
    let(:custom) { described_class.from_h(hash) }

    it '名前を付け替えても物理位置は変わらない' do
      expect(custom.matrix(custom.position('left_hand', 'row0', 'tab'))).to eq([0, 0])
      expect(custom.matrix(custom.position('left_hand', 'row1', 'lctrl'))).to eq([1, 0])
      expect(custom.matrix(custom.position('left_hand', 'row3', 'caps'))).to eq([3, 0])
      expect(custom.matrix(custom.position('left_hand', 'row3', 'fn'))).to eq([3, 1])
      expect(custom.position('left_hand', 'row3', 'lctrl')).to be_nil
    end

    it '内容が違えば等しくない' do
      expect(custom).not_to eq(map)
      expect(described_class.from_h(position_map_hash)).to eq(map)
      expect(described_class.from_h(position_map_hash).hash).to eq(map.hash)
    end
  end

  describe '#to_h / エンコーダのシンボル' do
    it 'position_map.yaml と同じ形に戻る' do
      expect(map.to_h).to eq(position_map_hash)
    end

    it 'エンコーダのシンボルを保持する' do
      expect(map.encoder_symbol(:left, 'push')).to eq('push')
      expect(map.encoder_symbol(:right, :cw)).to eq('cw')
    end

    it 'グループのシンボルを定義順に返す' do
      expect(map.symbols('right_hand', 'row3')).to eq(%w[left down right])
    end

    it '数字だけのシンボルは文字列にする' do
      hash = position_map_hash.tap { |h| h['left_hand']['row0'] = ['tab', 1, 2, 3, 4, 5] }
      expect(described_class.from_h(hash).position('left_hand', 'row0', '1')).to eq(key_position(:left, 0, 1))
    end
  end

  describe '構造検証' do
    def build(&edit)
      described_class.from_h(position_map_hash.tap(&edit))
    end

    it 'Hash でなければ InvalidValue' do
      expect { described_class.from_h(nil) }.to raise_error(Cornix::InvalidValue, /Hash/)
      expect { described_class.from_h([]) }.to raise_error(Cornix::InvalidValue)
    end

    it '手・グループ・エンコーダがなければ InvalidValue' do
      expect { build { |h| h.delete('right_hand') } }.to raise_error(Cornix::InvalidValue, /right_hand がありません/)
      expect { build { |h| h['left_hand'].delete('thumb_keys') } }
        .to raise_error(Cornix::InvalidValue, /left_hand.thumb_keys がありません/)
      expect { build { |h| h.delete('encoders') } }.to raise_error(Cornix::InvalidValue, /encoders がありません/)
      expect { build { |h| h['encoders'].delete('left') } }.to raise_error(Cornix::InvalidValue, /encoders.left がありません/)
      expect { build { |h| h['encoders']['right'].delete('cw') } }.to raise_error(Cornix::InvalidValue, /encoders.right.cw/)
    end

    it '各グループのキーの数（row0〜row2 は 6、row3 と thumb_keys は 3）' do
      expect { build { |h| h['left_hand']['row0'].pop } }.to raise_error(Cornix::InvalidValue, /left_hand.row0 は 6 個です: 5 個/)
      expect { build { |h| h['right_hand']['row3'] << 'extra' } }
        .to raise_error(Cornix::InvalidValue, /right_hand.row3 は 3 個です: 4 個/)
      expect { build { |h| h['right_hand']['thumb_keys'] = %w[a b] } }.to raise_error(Cornix::InvalidValue, /thumb_keys/)
    end

    it 'シンボルは [a-zA-Z0-9_-] の空でない文字列' do
      expect { build { |h| h['left_hand']['row0'][0] = 'ta b' } }.to raise_error(Cornix::InvalidValue, /row0\[0\]/)
      expect { build { |h| h['left_hand']['row0'][1] = nil } }.to raise_error(Cornix::InvalidValue, /row0\[1\]/)
      expect { build { |h| h['left_hand']['row0'][1] = '' } }.to raise_error(Cornix::InvalidValue)
      expect { build { |h| h['left_hand']['row0'][1] = "Q\nW" } }.to raise_error(Cornix::InvalidValue)
      expect { build { |h| h['encoders']['left']['push'] = 'pu.sh' } }.to raise_error(Cornix::InvalidValue, /encoders.left.push/)
    end

    it '同じグループの中でシンボルが重複すれば InvalidValue' do
      expect { build { |h| h['left_hand']['row1'][1] = 'S' } }
        .to raise_error(Cornix::InvalidValue, /left_hand.row1 でシンボル S が重複/)
    end

    it '問題をまとめて報告する' do
      expect do
        build do |h|
          h['left_hand']['row0'].pop
          h['right_hand']['row1'][0] = 'a b'
        end
      end.to raise_error(Cornix::InvalidValue, /left_hand.row0.*; .*right_hand.row1\[0\]/)
    end

    it 'new は直接呼べない（from_h を使う）' do
      expect { described_class.new(groups: {}, encoders: {}) }.to raise_error(NoMethodError)
    end
  end

  it 'freeze されている' do
    expect(map).to be_frozen
  end
end
