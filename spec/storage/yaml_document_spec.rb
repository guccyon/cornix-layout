# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Cornix::Storage::YamlDocument do
  let(:edit_class) { Cornix::Storage::TextEdit }

  def doc(text) = described_class.parse(text)
  def range(sl, sc, el, ec) = Cornix::Storage::TextRange.new(start_line: sl, start_character: sc, end_line: el, end_character: ec)

  def edited(text, path, value, **opts)
    edits = opts.key?(:order) ? doc(text).insert(path, value, **opts) : doc(text).replace(path, value)
    edit_class.apply(text, edits)
  end

  let(:layer) do
    <<~YAML
      ---
      name: Base
      index: 0
      mapping:
        left_hand:
          row0: { tab: Escape, Q: Q }
          row1:
            caps: Trans   # コメント
            A: { key: "@", note: アットマーク }
          row2:
          row3:
            fn: "-"
        right_hand:
          row0:
            Y: 'Y'
    YAML
  end

  describe '#range と #scalar' do
    it '値の範囲（行と列は 0 始まり）と表記を返す' do
      d = doc(layer)
      expect(d.range(%w[mapping left_hand row1 caps])).to eq(range(7, 12, 7, 17))
      expect(d.scalar(%w[mapping left_hand row1 caps])).to eq('Trans')
      expect(d.range(%w[mapping left_hand row0 Q])).to eq(range(5, 28, 5, 29))
      expect(d.range(%w[name])).to eq(range(1, 6, 1, 10))
    end

    it '引用符付きの値は引用符を含めた範囲で、表記は中身' do
      d = doc(layer)
      expect(d.range(%w[mapping left_hand row3 fn])).to eq(range(11, 10, 11, 13))
      expect(d.scalar(%w[mapping left_hand row3 fn])).to eq('-')
    end

    it '注記付きの形は key の値' do
      d = doc(layer)
      expect(d.range(%w[mapping left_hand row1 A])).to eq(range(8, 16, 8, 19))
      expect(d.scalar(%w[mapping left_hand row1 A])).to eq('@')
    end

    it 'ない場所は nil、値が空なら scalar は nil で range は名前の範囲' do
      d = doc(layer)
      expect(d.range(%w[mapping left_hand row2 Z])).to be_nil
      expect(d.scalar(%w[mapping nothing])).to be_nil
      expect(d.scalar(%w[mapping left_hand row2])).to be_nil
      expect(d.range(%w[mapping left_hand row2])).to eq(range(9, 4, 9, 8))
    end

    it '列は UTF-16 のコード単位（日本語は 1、絵文字は 2）' do
      d = doc("記号: { key: \"😀\", note: 日本語 }\n笑: 😀😀 x\n")
      expect(d.range(['記号'])).to eq(range(0, 11, 0, 15))
      expect(d.range(['笑'])).to eq(range(1, 3, 1, 9))
    end

    it '先頭の BOM は数えない（VS Code と同じ）' do
      expect(doc("﻿a: b\n").range(['a'])).to eq(range(0, 3, 0, 4))
    end

    it '並びの位置は整数で指す' do
      d = doc("sequence:\n  - { action: tap, keys: [A, B] }\n")
      expect(d.scalar(['sequence', 0, 'keys', 1])).to eq('B')
      expect(d.range(['sequence', 0, 'keys', 1])).to eq(range(1, 29, 1, 30))
    end

    it '複数行の値は終わりの行まで' do
      expect(doc("d: |-\n  a\n  b\nn: x\n").range(['d'])).to eq(range(0, 3, 2, 3))
    end
  end

  describe '#replace' do
    it '値の部分だけを置き換え、ほかの文字は変えない' do
      expect(edited(layer, %w[mapping left_hand row1 caps], 'LCtrl')).to eq(layer.sub('caps: Trans', 'caps: LCtrl'))
      expect(edited(layer, %w[mapping left_hand row0 tab], 'Tab')).to eq(layer.sub('tab: Escape', 'tab: Tab'))
    end

    it '同じ値なら書き換えを作らない（引用符の有無は問わない）' do
      d = doc(layer)
      expect(d.replace(%w[mapping left_hand row1 caps], 'Trans')).to eq([])
      expect(d.replace(%w[mapping left_hand row3 fn], '-')).to eq([])
      expect(d.replace(%w[mapping right_hand row0 Y], 'Y')).to eq([])
      expect(d.replace(%w[index], 0)).to eq([])
    end

    it 'YAML で引用符が要る値だけを囲む' do
      expect(edited(layer, %w[mapping left_hand row1 caps], ',')).to include('caps: ","   # コメント')
      expect(edited(layer, %w[mapping left_hand row1 caps], 'TapDance(\'Tab Escape\')')).to include("caps: TapDance('Tab Escape')")
      expect(edited(layer, %w[mapping left_hand row1 caps], 'Command + Shift + [')).to include('caps: Command + Shift + [')
      expect(edited(layer, %w[mapping left_hand row1 caps], 'true')).to include('caps: "true"')
      expect(edited(layer, %w[mapping left_hand row1 caps], '1')).to include('caps: "1"')
      expect(edited(layer, %w[mapping left_hand row1 caps], 'a: b')).to include('caps: "a: b"')
      expect(edited(layer, %w[mapping left_hand row1 caps], '"x"')).to include(%(caps: '"x"'))
    end

    it 'フロー表記の中では , や [ も囲む' do
      expect(edited(layer, %w[mapping left_hand row0 Q], 'Command + Shift + [')).to include('{ tab: Escape, Q: "Command + Shift + [" }')
      expect(edited(layer, %w[mapping left_hand row0 Q], 'W')).to include('{ tab: Escape, Q: W }')
    end

    it 'もとの引用符を保ち、同じ引用符を含む値はもう一方の引用符にする' do
      expect(edited(layer, %w[mapping left_hand row3 fn], 'Minus')).to include('fn: "Minus"')
      expect(edited(layer, %w[mapping right_hand row0 Y], 'Shortcut(\'前のタブへ\')')).to include(%(Y: "Shortcut('前のタブへ')"))
      expect(edited(layer, %w[mapping left_hand row3 fn], 'a"b')).to include(%(fn: 'a"b'))
    end

    it '注記付きの形は key の値だけを置き換え、note は残す' do
      expect(edited(layer, %w[mapping left_hand row1 A], 'A')).to include('A: { key: "A", note: アットマーク }')
    end

    it '値が空のキーはコロンのあとに値を書く' do
      text = "row1:\n  caps:   # なし\n  A: A\n"
      expect(edited(text, %w[row1 caps], 'Esc')).to eq("row1:\n  caps: Esc   # なし\n  A: A\n")
    end

    it '注記付きの形で key が空なら key のコロンのあとに書く（フロー・ブロック）' do
      flow = edited("a:\n  b: {key: , note: x}\n", %w[a b], 'Esc')
      expect(flow).to eq("a:\n  b: {key: Esc , note: x}\n") # コロンのあとの空白はそのまま
      expect(Psych.safe_load(flow)).to eq({ 'a' => { 'b' => { 'key' => 'Esc', 'note' => 'x' } } })
      expect(edited("a:\n  b:\n    key:\n    note: x\n", %w[a b], 'Esc')).to eq("a:\n  b:\n    key: Esc\n    note: x\n")
    end

    it 'key と note のほかのキーがあるマッピングは注記付きの形とみなさない' do
      text = "row0:\n  key: A\n  other: B\n"
      expect(doc(text).scalar(%w[row0])).to be_nil
      expect(doc(text).scalar(%w[row0 key])).to eq('A')
      expect { doc(text).replace(%w[row0], 'X') }
        .to raise_error(Cornix::Storage::EditNotLocal) { |e| expect(e.reason).to eq(:multiline) }
    end

    it '制御文字は二重引用符の中でエスケープする' do
      result = edited("a: b\n", ['a'], "x\u0001y\ttab")
      expect(result).to eq("a: \"x\\x01y\\ttab\"\n")
      expect(Psych.safe_load(result)).to eq({ 'a' => "x\u0001y\ttab" })
    end

    it 'UTF-8 でない文字列（BINARY）も UTF-8 として読む' do
      expect(doc('ベース: a'.b).scalar(['ベース'])).to eq('a')
    end

    it '整数と真偽値はそのまま書く（QMK 設定）' do
      text = "keyboard:\n  tapping_term: 180\n  permissive_hold: false\n"
      expect(edited(text, %w[keyboard tapping_term], 200)).to eq(text.sub('180', '200'))
      expect(edited(text, %w[keyboard permissive_hold], true)).to eq(text.sub('false', 'true'))
    end

    it '日本語と絵文字のある行でも位置がずれない' do
      text = "記号: { key: \"😀\", note: 日本語 }\n"
      expect(edited(text, ['記号'], 'Ⓐ')).to eq("記号: { key: \"Ⓐ\", note: 日本語 }\n")
    end

    it 'CRLF と BOM はそのまま' do
      text = "﻿a: b\r\nc: d\r\n"
      expect(edited(text, ['c'], 'e')).to eq("﻿a: b\r\nc: e\r\n")
    end

    it '複数行の値・アンカーとエイリアスは EditNotLocal' do
      expect { doc("d: |-\n  a\n  b\n").replace(['d'], 'x') }
        .to raise_error(Cornix::Storage::EditNotLocal) { |e| expect([e.reason, e.path]).to eq([:multiline, ['d']]) }
      expect { doc("d: \"a\n  b\"\n").replace(['d'], 'x') }
        .to raise_error(Cornix::Storage::EditNotLocal) { |e| expect(e.reason).to eq(:multiline) }
      expect { doc("a: &x y\nb: *x\n").replace(['a'], 'z') }
        .to raise_error(Cornix::Storage::EditNotLocal) { |e| expect(e.reason).to eq(:anchor) }
      expect { doc("a: &x { k: y }\nb: *x\n").replace(%w[b k], 'z') }
        .to raise_error(Cornix::Storage::EditNotLocal) { |e| expect(e.reason).to eq(:anchor) }
    end

    it 'ない場所は ArgumentError（insert を使う）' do
      expect { doc(layer).replace(%w[mapping left_hand row2 Z], 'Z') }.to raise_error(ArgumentError)
    end
  end

  describe '#insert' do
    let(:group_order) { %w[caps A S D F G] }

    it 'ブロック形式のグループの、並びの順の場所に足す' do
      text = "row1:\n  caps: Trans\n  D: D   # d\n  G: G\n"
      expect(edited(text, %w[row1 S], 'S', order: group_order)).to eq("row1:\n  caps: Trans\n  S: S\n  D: D   # d\n  G: G\n")
      expect(edited(text, %w[row1 F], 'F', order: group_order)).to eq("row1:\n  caps: Trans\n  D: D   # d\n  F: F\n  G: G\n")
      expect(edited(text, %w[row1 Z], 'Z', order: group_order)).to eq("row1:\n  caps: Trans\n  D: D   # d\n  G: G\n  Z: Z\n")
    end

    it '並びの先頭に来るキーは最初のキーの前に足す' do
      text = "# 先頭\nrow1:\n  # コメント\n  A: A\n"
      expect(edited(text, %w[row1 caps], 'Esc', order: group_order)).to eq("# 先頭\nrow1:\n  # コメント\n  caps: Esc\n  A: A\n")
    end

    it '入れ子の値のあと（最後の行の次）に足す' do
      text = "mapping:\n  left_hand:\n    row0:\n      tab: Tab\n  encoders:\n    left:\n      push: Mute\n"
      order = { %w[mapping] => %w[left_hand right_hand encoders] }
      expect(edited(text, %w[mapping right_hand row0 Y], 'Y', order: order))
        .to eq("mapping:\n  left_hand:\n    row0:\n      tab: Tab\n  right_hand:\n    row0:\n      Y: Y\n  encoders:\n    left:\n      push: Mute\n")
    end

    it '値なしのグループ見出しの下に字下げして足す（~ も）' do
      text = "  # x\nmapping:\n  row2:   # 空\n  row3: ~\n"
      expect(edited(text, %w[mapping row2 Z], ',', order: [])).to eq("  # x\nmapping:\n  row2:   # 空\n    Z: \",\"\n  row3: ~\n")
      expect(edited(text, %w[mapping row3 caps], 'Esc', order: [])).to eq("  # x\nmapping:\n  row2:   # 空\n  row3:\n    caps: Esc\n")
    end

    it '空のフロー表記（{}。足したレイヤーの形）の見出しは、{} を消して下に字下げして足す' do
      text = "mapping:\n  left_hand:\n    row0: {}\n    row1: {}  # 空\n"
      expect(edited(text, %w[mapping left_hand row1 A], 'A', order: []))
        .to eq("mapping:\n  left_hand:\n    row0: {}\n    row1:  # 空\n      A: A\n")
      expect(edited(text, %w[mapping left_hand row0 Q], 'Q', order: []))
        .to eq("mapping:\n  left_hand:\n    row0:\n      Q: Q\n    row1: {}  # 空\n")
    end

    it '中身のあるフロー表記の中には足さない' do
      text = "mapping:\n  left_hand:\n    row0: { Q: Q }\n"
      expect { edited(text, %w[mapping left_hand row0 W], 'W', order: []) }.to raise_error(Cornix::Storage::EditNotLocal)
    end

    it 'グループの見出しや mapping: ごとないときも並びの順に見出しを足す' do
      text = "name: Base\nindex: 0\n"
      order = { [] => %w[name index description mapping] }
      expect(edited(text, %w[mapping left_hand row0 tab], 'Tab', order: order))
        .to eq("name: Base\nindex: 0\nmapping:\n  left_hand:\n    row0:\n      tab: Tab\n")
      text = "mapping:\n  left_hand:\n    row1:\n      caps: A\n"
      order = { %w[mapping left_hand] => %w[row0 row1 row2 row3 thumb_keys] }
      expect(edited(text, %w[mapping left_hand row0 tab], 'Tab', order: order))
        .to eq("mapping:\n  left_hand:\n    row0:\n      tab: Tab\n    row1:\n      caps: A\n")
    end

    it 'ファイルの字下げの幅に合わせる' do
      text = "keyboard:\n    tapping_term: 180\nvial:\n"
      expect(edited(text, %w[vial combo_timing_window], 50, order: []))
        .to eq("keyboard:\n    tapping_term: 180\nvial:\n    combo_timing_window: 50\n")
    end

    it '空のファイルと --- だけのファイルには最初から書く' do
      expect(edited('', %w[keyboard tapping_term], 180, order: [])).to eq("keyboard:\n  tapping_term: 180\n")
      expect(edited("---\n", %w[keyboard tapping_term], 180, order: [])).to eq("---\nkeyboard:\n  tapping_term: 180\n")
    end

    it '文書全体が ~ や null なら、それを消して最初から書く' do
      expect(edited("--- ~\n", %w[keyboard t], 180, order: [])).to eq("---\nkeyboard:\n  t: 180\n")
      expect(edited("null\n", %w[keyboard t], 180, order: [])).to eq("\nkeyboard:\n  t: 180\n")
      expect(Psych.safe_load(edited("--- ~ # c\n", %w[keyboard t], 180, order: []))).to eq({ 'keyboard' => { 't' => 180 } })
    end

    it '並びの中の空の要素には足せない（ArgumentError）' do
      expect { doc("a:\n  -\n  - x\nb: 1\n").insert(['a', 0, 'k'], 'v') }.to raise_error(ArgumentError)
    end

    it 'CR だけのファイルには CR で足す' do
      expect(edited("row1:\r  caps: A\r", %w[row1 A], 'A', order: group_order)).to eq("row1:\r  caps: A\r  A: A\r")
    end

    it 'CRLF のファイルには CRLF で足す' do
      text = "row1:\r\n  caps: A\r\n"
      expect(edited(text, %w[row1 A], 'A', order: group_order)).to eq("row1:\r\n  caps: A\r\n  A: A\r\n")
    end

    it 'もうあれば replace と同じ' do
      text = "row1:\n  caps: A\n"
      expect(doc(text).insert(%w[row1 caps], 'B', order: group_order)).to eq(doc(text).replace(%w[row1 caps], 'B'))
    end

    it 'フロー表記の中へは足さない（EditNotLocal）' do
      expect { doc(layer).insert(%w[mapping left_hand row0 W], 'W', order: %w[tab Q W]) }
        .to raise_error(Cornix::Storage::EditNotLocal) { |e| expect(e.reason).to eq(:flow_insert) }
    end

    it '値の中や並びの中には足せない（ArgumentError）' do
      expect { doc("a: b\n").insert(%w[a c], 'x') }.to raise_error(ArgumentError)
      expect { doc("a: [x]\n").insert(['a', 1], 'y') }.to raise_error(ArgumentError)
    end
  end
end
