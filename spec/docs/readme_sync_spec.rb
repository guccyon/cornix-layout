# frozen_string_literal: true

require 'spec_helper'

# README.md（英語）と README.ja.md（日本語）が同じ構成になっていることを確かめる。
# 片方だけに節やコード例を足すと落ちる（.claude/CLAUDE.md の「README の同期」）
RSpec.describe 'README の英語版と日本語版の同期' do
  def read(name) = File.read(File.join(Cornix::ROOT, name), encoding: 'UTF-8')

  # コードブロックの外の見出しのレベル、コードブロックの言語、リポジトリ内のファイルと外部へのリンク、節へのリンクの数
  def structure(text)
    headings = []
    fences = []
    links = []
    urls = []
    section_links = 0
    in_code = false
    text.each_line do |line|
      if (m = line.match(/\A```(\S*)/))
        fences << m[1] unless in_code
        in_code = !in_code
        next
      end
      next if in_code

      headings << line[/\A#+/].size if line.match?(/\A#+ /)
      targets = line.scan(/\]\(([^)#][^)]*)\)/).flatten
      urls.concat(targets.grep(%r{\A[a-z]+://}))
      links.concat(targets.grep_v(%r{\A[a-z]+://}))
      section_links += line.scan(/\]\(#/).size
    end
    { headings: headings, fences: fences, links: links.reject { |l| l.start_with?('README') }, urls: urls,
      section_links: section_links }
  end

  let(:en) { structure(read('README.md')) }
  let(:ja) { structure(read('README.ja.md')) }

  it '見出しのレベルの並びが同じ' do
    expect(en[:headings]).to eq(ja[:headings])
  end

  it 'コードブロックの数と言語の指定が同じ' do
    expect(en[:fences]).to eq(ja[:fences])
  end

  it 'リポジトリ内のファイルへのリンクが同じ' do
    expect(en[:links]).to eq(ja[:links])
  end

  it '外部へのリンクが同じ' do
    expect(en[:urls]).to eq(ja[:urls])
  end

  it '節へのリンク（#...）の数が同じ' do
    expect(en[:section_links]).to eq(ja[:section_links])
  end

  it 'リポジトリ内のファイルへのリンク先がある' do
    (en[:links] | ja[:links]).each do |link|
      expect(File).to exist(File.join(Cornix::ROOT, link)), link
    end
  end

  # GitHub と同じ規則で見出しからアンカーを作る（記号を消し、空白を - にする）
  def anchors(text)
    in_code = false
    text.each_line.filter_map do |line|
      in_code = !in_code if line.start_with?('```')
      next if in_code || !line.match?(/\A#+ /)

      line.sub(/\A#+ /, '').strip.downcase.gsub(/[^\p{L}\p{N}\p{M}\- _]/, '').tr(' ', '-')
    end
  end

  %w[README.md README.ja.md].each do |name|
    it "#{name} の節へのリンク（#...）の行き先がある" do
      text = read(name)
      targets = text.scan(/\]\(#([^)]+)\)/).flatten.uniq
      expect(targets - anchors(text)).to eq([])
    end
  end

  it 'それぞれの先頭に、もう一方へのリンクがある' do
    expect(read('README.md').lines.first(5).join).to include('[日本語](README.ja.md)')
    expect(read('README.ja.md').lines.first(5).join).to include('[English](README.md)')
  end
end
