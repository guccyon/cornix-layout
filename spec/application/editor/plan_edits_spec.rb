# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'

# 応答の形の約束は spec/fixtures/protocol/profile_plan_edits（適合テスト）。ここでは書き換えの細かい振る舞いを確かめる
RSpec.describe Cornix::Application::Editor::PlanEdits do

  around do |example|
    Dir.mktmpdir('cornix-plan-edits') do |dir|
      @root = File.realpath(dir)
      FileUtils.cp_r(File.join(__dir__, '../../fixtures/test_config'), File.join(@root, 'profile'))
      example.run
    end
  end

  let(:workbench) { Cornix::Application::Editor::Workbench.new(root: @root) }
  let(:opened) { workbench.open('profile') }
  let(:layer) { 'layers/0_layer_0.yaml' }
  let(:settings) { 'settings/qmk_settings.yaml' }

  def path(rel) = File.join(@root, 'profile', rel)
  def read(rel) = File.read(path(rel))
  def write(rel, text) = File.write(path(rel), text)
  def version(rel) = Cornix::Storage::FileVersion.read(path(rel))

  def plan(changes, base_versions: changes.map(&:file).uniq.to_h { |f| [f, version(f)] })
    described_class.new(workbench).call(opened.id, base_versions: base_versions, changes: changes)
  end

  def change(file, path, value) = described_class::Change.new(file: file, path: path, value: value)

  # 書き換えを当てたテキスト
  def applied(result, file)
    entry = result[:files].find { |f| f[:file] == file }
    edits = entry[:edits].map do |e|
      r = e[:range]
      range = Cornix::Storage::TextRange.new(start_line: r[:start][:line], start_character: r[:start][:character],
                                             end_line: r[:end][:line], end_character: r[:end][:character])
      Cornix::Storage::TextEdit.new(range: range, new_text: e[:newText])
    end
    Cornix::Storage::TextEdit.apply(File.exist?(path(file)) ? read(file) : '', edits)
  end

  it 'ファイルは書かない' do
    before = read(layer)
    plan([change(layer, %w[mapping left_hand row0 tab], 'Escape')])
    expect(read(layer)).to eq(before)
  end

  it '書き換えを当てると、値の部分だけが変わる（ほかの行・コメントはそのまま）' do
    write(layer, read(layer).sub('      Q: Q', "      Q: Q # コメント\n      # 行のコメント"))
    result = plan([change(layer, %w[mapping left_hand row0 Q], 'Escape'), change(layer, %w[mapping right_hand row0 U], 'Macro(0)')])
    expect(applied(result, layer)).to eq(read(layer).sub('Q: Q #', 'Q: Escape #').sub('U: U', 'U: Macro(0)'))
  end

  it 'エンコーダの操作の値を置き換える' do
    result = plan([change(layer, %w[mapping encoders right push], 'Mute')])
    expect(applied(result, layer)).to eq(read(layer).sub('push: OSL(9)', 'push: Mute'))
  end

  it '引用符が要る値は囲み、もとの引用符は保つ' do
    result = plan([change(layer, %w[mapping left_hand row0 tab], ','), change(layer, %w[mapping right_hand row1 colon], "'")])
    expect(applied(result, layer)).to eq(read(layer).sub('tab: Tab', 'tab: ","').sub('colon: ";"', %(colon: "'")))
  end

  it 'CRLF のファイルでも行の終わりの形を保つ' do
    write(layer, read(layer).gsub("\n", "\r\n"))
    result = plan([change(layer, %w[mapping left_hand row2 lshift], 'Escape')])
    expect(applied(result, layer)).to eq(read(layer).sub('lshift: LShift', 'lshift: Escape'))
  end

  describe 'QMK 設定' do
    it '整数の設定は整数で書き、範囲を超えれば構造の error（保存は拡張が止める）' do
      result = plan([change(settings, ['7'], 70_000)])
      expect(applied(result, settings)).to include("'7': 70000")
      expect(result[:diagnostics]).to contain_exactly(include(severity: 'error', source: 'structure',
                                                              address: { file: settings, path: ['7'] }))
    end

    it '真偽値の設定は 0 / 1 も受け付ける' do
      result = plan([change(settings, ['23'], 1)])
      expect(applied(result, settings)).to include("'23': 1")
    end

    it 'ファイルが true / false で書いていれば true / false で書く' do
      write(settings, "keyboard:\n  permissive_hold: false\n")
      result = plan([change(settings, %w[keyboard permissive_hold], 1)])
      expect(applied(result, settings)).to eq("keyboard:\n  permissive_hold: true\n")
    end

    it '名前の形のファイルでは、group の下の data/qmk_settings.yaml の順の場所に足す' do
      write(settings, "keyboard:\n  oneshot_timeout: 1000\n  tap_code_delay: 20\nvial:\n  combo_timing_window: 50\n")
      result = plan([change(settings, %w[keyboard tapping_term], 200)])
      expect(applied(result, settings))
        .to eq("keyboard:\n  oneshot_timeout: 1000\n  tapping_term: 200\n  tap_code_delay: 20\nvial:\n  combo_timing_window: 50\n")
    end

    it '名前の形の設定は、旧 QSID の番号の形で書いてあれば番号の場所しか指せない' do
      expect { plan([change(settings, %w[keyboard tapping_term], 200)]) }
        .to raise_error(described_class::InvalidChange) { |e| expect(e.field).to eq('changes[0].address') }
    end
  end

  describe '値の部分だけでは書き換えられないとき（NotLocal）' do
    # アンカーとエイリアスは読み込みで構造の問題になる（プロファイル全体が読めず、宛先がない）ので、ここでは複数行の値だけ
    it '複数行の値' do
      write(layer, read(layer).sub("tab: Tab\n", "tab: |\n        Tab\n"))
      expect { plan([change(layer, %w[mapping left_hand row0 tab], 'Escape')]) }
        .to raise_error(described_class::NotLocal) { |e| expect(e.reason).to eq('multiline') }
    end
  end

  describe '確かめる順と失敗' do
    it 'baseVersions の食い違いは宛先より先に確かめ、食い違ったファイルの今の版を持つ' do
      expect do
        plan([change(layer, %w[nope], 'X')], base_versions: { layer => 'sha256:00', settings => version(settings) })
      end.to raise_error(described_class::VersionConflict) { |e| expect(e.files).to eq(layer => version(layer)) }
    end

    it '設定ファイルでないファイルの版は null として比べる' do
      expect { plan([], base_versions: { 'README.md' => 'sha256:00' }) }
        .to raise_error(described_class::VersionConflict) { |e| expect(e.files).to eq('README.md' => nil) }
    end

    it '構造検証で読めないプロファイルには宛先がない（変更がなければ構造の問題を返す）' do
      write(layer, read(layer).sub('tab: Tab', "tab: Macro('Removed')"))
      expect { plan([change(layer, %w[mapping left_hand row0 tab], 'Tab')]) }.to raise_error(described_class::InvalidChange)
      expect(plan([])[:diagnostics]).to contain_exactly(include(source: 'structure'))
    end

    it '同じ Address への変更は最後の値になる' do
      result = plan([change(layer, %w[mapping left_hand row0 tab], 'Escape'), change(layer, %w[mapping left_hand row0 tab], 'Enter')])
      expect(applied(result, layer)).to eq(read(layer).sub('tab: Tab', 'tab: Enter'))
    end

    it '変更しても元と同じ中身になるファイルは files に入れない' do
      result = plan([change(layer, %w[mapping left_hand row0 tab], 'Escape'), change(layer, %w[mapping left_hand row0 tab], 'Tab')])
      expect(result[:files]).to eq([])
    end
  end
end
