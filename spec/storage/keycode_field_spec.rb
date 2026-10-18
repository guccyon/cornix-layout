# frozen_string_literal: true

require 'spec_helper'
require_relative 'support/storage_helpers'

RSpec.describe Cornix::Storage::Schema::KeycodeField do
  include StorageHelpers

  subject(:field) { described_class.new(notation) }

  let(:k) { Cornix::Domain::Keycode }
  let(:problems) { Cornix::Storage::Problems.new }
  let(:ctx) { Cornix::Storage::Schema::Context.new('x.yaml', problems) }
  let(:btn1) { k::Basic.new(code: 0xD1) }

  def assignment(keycode, note = nil) = described_class::Assignment.new(keycode: keycode, note: note)
  def messages = problems.to_a.map(&:to_s)

  describe '#read_assignment' do
    it '3 通りの書き方を読む' do
      expect(field.read_assignment({ 'key' => 'MouseButton1', 'note' => '左クリック' }, ctx, 'a'))
        .to eq(assignment(btn1, '左クリック'))
      expect(field.read_assignment({ 'key' => 'MouseButton1' }, ctx, 'a')).to eq(assignment(btn1))
      expect(field.read_assignment('MouseButton1', ctx, 'a')).to eq(assignment(btn1))
      expect(messages).to be_empty
    end

    it 'nil は default があれば注記なしの default、なければ問題' do
      expect(field.read_assignment(nil, ctx, 'a', default: k::NO_KEY)).to eq(assignment(k::NO_KEY))
      expect(field.read_assignment(nil, ctx, 'a')).to be_nil
      expect(messages).to include(a_string_matching(/x.yaml: a: キーコード（文字列）か/))
    end

    it '空白だけの注記は注記なし、文字列でない注記・未知のキーは問題' do
      expect(field.read_assignment({ 'key' => 'A', 'note' => ' ' }, ctx, 'a').note).to be_nil
      expect(field.read_assignment({ 'key' => 'A', 'note' => 1 }, ctx, 'b')).to be_nil
      expect(field.read_assignment({ 'key' => 'A', 'memo' => 'x' }, ctx, 'c')).not_to be_nil
      expect(messages).to include(a_string_matching(/b.note: 注記（文字列）/), a_string_matching(/c.memo: 未知のキー/))
    end
  end

  describe '#write_assignment' do
    it '注記があれば key / note、なければキーコードの文字列' do
      expect(field.write_assignment(btn1, '左クリック')).to eq('key' => 'MouseButton1', 'note' => '左クリック')
      expect(field.write_assignment(btn1, nil)).to eq('MouseButton1')
    end
  end

  it '.notes は注記のある場所だけを集める' do
    expect(described_class.notes(a: assignment(btn1, 'x'), b: assignment(btn1))).to eq(a: 'x')
  end
end
