# frozen_string_literal: true

require 'spec_helper'
require_relative 'support/storage_helpers'

# 実データ（authors-keymap の config の複写）で、値をいくつか書き換えても変えていない行が 1 バイトも変わらないこと
RSpec.describe 'Storage::YamlDocument（実データ）' do
  include StorageHelpers

  let(:source) { Cornix::Storage::FileSource::Disk.new(StorageHelpers::AUTHORS_CONFIG) }
  let(:groups) { %w[row0 row1 row2 row3 thumb_keys] }

  # rel のファイルに [path, value] を 1 つずつ当てる（足すときは order を付ける）。[元, 書き換えたあと]
  def edit_file(rel, changes, text: source.read(rel))
    edited = changes.reduce(text) do |current, (path, value, order)|
      doc = Cornix::Storage::YamlDocument.parse(current)
      edits = order ? doc.insert(path, value, order: order) : doc.replace(path, value)
      Cornix::Storage::TextEdit.apply(current, edits)
    end
    [text, edited]
  end

  # 書き換えたあとの行のうち、書き換えた行（changed）と足した行（added）以外は元の行とバイト列まで同じ
  def expect_untouched(before, after, changed:, added: [])
    old_lines = before.lines
    new_lines = after.lines
    kept = new_lines.each_index.reject { |i| added.include?(i) }
    expect(kept.size).to eq(old_lines.size)
    kept.each_with_index do |new_index, old_index|
      next if changed.include?(old_index)

      expect(new_lines[new_index].b).to eq(old_lines[old_index].b), "#{old_index + 1} 行目が変わりました"
    end
  end

  # 元のテキストで line と同じ行の位置（0 始まり）
  def line_of(text, line) = text.lines.index(line) || raise("#{line.inspect} がありません")

  def position(profile, hand, group, symbol) = profile.position_map.position(hand, group, symbol)
  def keycode(text) = notation.parse(text)

  it 'レイヤーの値（引用符付き・関数形式・エンコーダ）を書き換えても、ほかの行は変わらない' do
    changes = [
      [%w[mapping left_hand row0 tab], 'Escape'],
      [%w[mapping right_hand row1 colon], 'Minus'],
      [%w[mapping right_hand row2 comma], 'Command + Shift + ['],
      [%w[mapping left_hand thumb_keys middle], 'LT2(Space)'],
      [%w[mapping encoders right push], "Macro('Bracket Pair')"],
      [%w[mapping left_hand row0 Q], 'Q'] # 同じ値は書き換えない
    ]
    before, after = edit_file('layers/0_base.yml', changes)
    changed = ["      tab: TapDance('Tab Escape')\n", "      colon: \"-\"\n", "      comma: \",\"\n",
               "      middle: LT1(Space)\n", "      push: TapDance('Layer 3 Toggle')\n"].map { |line| line_of(before, line) }
    expect(changed.map { |i| after.lines[i] })
      .to eq(["      tab: Escape\n", "      colon: \"Minus\"\n", "      comma: \"Command + Shift + [\"\n",
              "      middle: LT2(Space)\n", "      push: Macro('Bracket Pair')\n"])
    expect_untouched(before, after, changed: changed)

    profile = repository(StorageHelpers::AUTHORS_CONFIG).then do |repo|
      Cornix::Storage::ConfigRepository.new(repo.dir, notation: notation, settings_catalog: settings_catalog,
                                            source: Cornix::Storage::FileSource::Overlay.new(source, 'layers/0_base.yml' => after))
    end.load
    layer = profile.layer(0)
    expect(layer.key(position(profile, 'left_hand', 'row0', 'tab'))).to eq(keycode('Escape'))
    expect(layer.key(position(profile, 'right_hand', 'row2', 'comma'))).to eq(keycode('Command + Shift + ['))
    expect(layer.key(position(profile, 'left_hand', 'row0', 'Q'))).to eq(keycode('Q'))
  end

  it '複数行の説明のあるレイヤーと QMK 設定でも、ほかの行は変わらない' do
    before, after = edit_file('layers/1_symbols.yml', [[%w[mapping left_hand row1 A], 'At'],
                                                        [%w[mapping left_hand row0 R], 'Tilde']])
    changed = [line_of(before, "      A: \"@\"\n"), line_of(before, "      R: NoKey\n")]
    expect(changed.map { |i| after.lines[i] }).to eq(["      A: \"At\"\n", "      R: Tilde\n"])
    expect_untouched(before, after, changed: changed)

    before, after = edit_file('settings/qmk_settings.yaml', [[%w[keyboard tapping_term], 200],
                                                              [%w[keyboard permissive_hold], true]])
    changed = [line_of(before, "  tapping_term: 180\n"), line_of(before, "  permissive_hold: false\n")]
    expect(changed.map { |i| after.lines[i] }).to eq(["  tapping_term: 200\n", "  permissive_hold: true\n"])
    expect_untouched(before, after, changed: changed)
  end

  it 'まだない場所（消したキー・ない QMK 設定・ない見出し）に足しても、ほかの行は変わらない' do
    base = source.read('layers/0_base.yml')
    removed = base.sub("      X: X\n", '').sub(/    thumb_keys:\n      left: MO\(3\)\n      middle: MO\(1\)\n      right: LT2\(KC_LANG1\)\n/, '')
    order = { %w[mapping left_hand row2] => %w[lshift Z X C V B], %w[mapping right_hand] => groups,
              %w[mapping right_hand thumb_keys] => %w[left middle right] }
    before, after = edit_file('layers/0_base.yml', [[%w[mapping left_hand row2 X], 'Shift + X', order],
                                                    [%w[mapping right_hand thumb_keys middle], 'MO(1)', order]],
                              text: removed)
    x = line_of(after, "      X: Shift + X\n")
    expect(after.lines[x - 2..x + 1]).to eq(["      lshift: LShift\n", "      Z: Z\n", "      X: Shift + X\n", "      C: C\n"])
    thumb = line_of(after, "      middle: MO(1)\n")
    expect(after.lines[thumb - 2..]).to eq(["      right: Right\n", "    thumb_keys:\n", "      middle: MO(1)\n",
                                            "  encoders:\n", *before.lines.drop_while { |l| l != "  encoders:\n" }.drop(1)])
    expect_untouched(before, after, changed: [], added: [x, thumb - 1, thumb])
    layer_after = after

    settings = source.read('settings/qmk_settings.yaml').sub("  tap_code_delay: 20\n", '')
    settings_order = settings_catalog.all.select { |d| d.group == 'keyboard' }.map(&:name)
    before, after = edit_file('settings/qmk_settings.yaml', [[%w[keyboard tap_code_delay], 20, settings_order]],
                              text: settings)
    added = line_of(after, "  tap_code_delay: 20\n")
    expect(after.lines[added - 1]).to eq("  tapping_term: 180\n")
    expect_untouched(before, after, changed: [], added: [added])

    overlay = Cornix::Storage::FileSource::Overlay.new(source, 'layers/0_base.yml' => layer_after,
                                                               'settings/qmk_settings.yaml' => after)
    profile = Cornix::Storage::ConfigRepository.new(source.dir, notation: notation, settings_catalog: settings_catalog,
                                                    source: overlay).load
    disk = repository(StorageHelpers::AUTHORS_CONFIG).load
    expect(profile.layer(0).key(position(profile, 'left_hand', 'row2', 'X'))).to eq(keycode('Shift + X'))
    expect(profile.layer(0).key(position(profile, 'right_hand', 'thumb_keys', 'middle'))).to eq(keycode('MO(1)'))
    expect(profile.settings).to eq(disk.settings)
  end
end
