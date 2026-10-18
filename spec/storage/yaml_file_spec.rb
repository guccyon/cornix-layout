# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Cornix::Storage::YamlFile do
  around do |example|
    Dir.mktmpdir { |dir| @dir = dir; example.run }
  end

  def read(text)
    path = File.join(@dir, 'a.yaml')
    File.write(path, text)
    described_class.read(path)
  end

  def unreadable(text)
    expect { read(text) }.to raise_error(described_class::Unreadable) { |e| return e.message }
  end

  describe '.read' do
    it '文字列・数値・真偽値・nil・配列・マッピングを読む' do
      expect(read("a: 1\nb: [x, true]\nc:\n")).to eq('a' => 1, 'b' => ['x', true], 'c' => nil)
    end

    it '空のファイルは nil、先頭の BOM は無視する' do
      expect(read('')).to be_nil
      expect(read("\uFEFFa: 1\n")).to eq('a' => 1)
    end

    it 'キーの重複はエラー（行番号つき）' do
      expect(unreadable("a: 1\nb: 2\na: 3\n")).to include('キー「a」が重複しています（3 行）')
    end

    it '入れ子のマッピングのキーの重複もエラー' do
      expect(unreadable("m:\n  x: 1\n  x: 2\n")).to include('キー「x」が重複しています')
    end

    it 'アンカーとエイリアスはエラー' do
      expect(unreadable("a: &x 1\nb: *x\n")).to include('使えません')
    end

    it '文法エラーは行と桁を示す' do
      expect(unreadable("a: [1, 2\nb: 3\n")).to match(/YAML の文法エラーです（\d+ 行 \d+ 桁）/)
    end

    it '日付などの型はエラー' do
      expect(unreadable("a: 2024-01-01\n")).to include('引用符で囲んで')
    end

    it 'UTF-8 でないファイルはエラー' do
      expect(unreadable("a: \xFF\n".b)).to include('UTF-8')
    end
  end

  describe '.dump' do
    it '先頭に --- を付け、末尾は改行で終わる' do
      expect(described_class.dump({ 'a' => 'x' })).to eq("---\na: x\n")
    end

    it '旧 WriterHelpers.minimize_quotes と同じく、要らない引用符を外す' do
      text = described_class.dump({ 'Y' => 'Y', 'semi' => ';', 'num' => '1', 'bs' => '\\', 'empty' => '', 'w' => 'no' })
      expect(text).to include(%("Y": Y\n))
      expect(text).to include(%(semi: ";"\n))
      expect(text).to include(%(num: '1'\n))
      expect(text).to include(%(bs: "\\\\"\n))
      expect(text).to include(%(empty: ''\n))
      expect(text).to include(%(w: 'no'\n))
    end

    it '外すと別の値になる引用符は外さない' do
      data = { 'a' => '.inf', 'b' => '~', 'c' => '.', 'd' => '=', 'e' => '<<', 'f' => 'Cmd + Shift + 4' }
      expect(Psych.safe_load(described_class.dump(data))).to eq(data)
    end

    it 'flow: true ならスカラーだけの配列を 1 行で書く' do
      text = described_class.dump({ 'row0' => %w[tab Q], 'm' => { 'x' => 'y' } }, flow: true)
      expect(text).to include("row0: [tab, Q]\n")
    end

    it '長い文字列を折り返さない' do
      long = 'あ' * 200
      expect(described_class.dump({ 'd' => long })).to eq("---\nd: #{long}\n")
    end
  end
end
