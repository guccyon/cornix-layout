# frozen_string_literal: true

require 'spec_helper'

# YamlDocument の項目の削除・並びの要素の挿入と移動・注記の書き換え（protocol.md の 12.3）
RSpec.describe Cornix::Storage::YamlDocument do
  def doc(text) = described_class.parse(text)
  def apply(text, edits) = Cornix::Storage::TextEdit.apply(text, edits)
  def removed(text, path) = apply(text, doc(text).remove(path))
  def inserted(text, path, index, value) = apply(text, doc(text).insert_item(path, index, value))
  def moved(text, path, from, to) = apply(text, doc(text).move_item(path, from, to))

  let(:macro) do
    <<~YAML
      ---
      index: 0
      name: M
      sequence:
      - action: tap
        keys:
        - KC_A
        - KC_B # B のコメント
      # 手順 1 の前のコメント
      - action: down
        keys: KC_C
      - action: delay
        duration: 10
    YAML
  end

  describe '#remove' do
    it 'ブロック形式の項目は行ごと消す（ほかの行・コメントはそのまま）' do
      text = "mapping:\n  row0:\n    tab: Tab # コメント\n    Q: Q\n"
      expect(removed(text, %w[mapping row0 tab])).to eq("mapping:\n  row0:\n    Q: Q\n")
    end

    it '最後の項目を消しても見出しは残る。改行のないファイルの最後の行も消せる' do
      expect(removed("row0:\n  tab: Tab\nrow1:\n  A: A", %w[row1 A])).to eq("row0:\n  tab: Tab\nrow1:")
    end

    it '値が入れ子の項目は中の行ごと消す' do
      expect(removed("a:\n  key: Q\n  note: x\nb: 1\n", ['a'])).to eq("b: 1\n")
    end

    it '1 行のフロー表記の Hash は項目と区切りだけを消す。最後の 1 つなら {}' do
      text = "row1: { caps: LCtrl, A: A, S: S }\n"
      expect(removed(text, %w[row1 A])).to eq("row1: { caps: LCtrl, S: S }\n")
      expect(removed(text, %w[row1 caps])).to eq("row1: { A: A, S: S }\n")
      expect(removed("row1: { caps: LCtrl }\n", %w[row1 caps])).to eq("row1: {}\n")
    end

    it 'ブロック形式の並びの要素は行ごと消す（行の終わりのコメントも）' do
      expect(removed(macro, ['sequence', 0, 'keys', 1])).to eq(macro.sub("  - KC_B # B のコメント\n", ''))
      expect(removed(macro, ['sequence', 2])).to eq(macro.sub("- action: delay\n  duration: 10\n", ''))
    end

    it '「-」だけの行のあとに書いた要素は「-」の行から消す' do
      expect(removed("s:\n- a\n-\n  b: 1\n- c\n", ['s', 1])).to eq("s:\n- a\n- c\n")
    end

    it 'フロー表記の並びの要素は、並びを 1 行で書き直す（内側の空白は保つ）' do
      expect(removed("k: [KC_A, KC_B, KC_C]\n", ['k', 1])).to eq("k: [KC_A, KC_C]\n")
      expect(removed("k: [ KC_A, 'KC_B' ]\n", ['k', 0])).to eq("k: [ 'KC_B' ]\n")
    end

    it 'ない場所は []' do
      expect(doc(macro).remove(%w[nope])).to eq([])
      expect(doc(macro).remove(['sequence', 9])).to eq([])
    end

    it '前に別の内容がある行の項目と、複数行のフロー表記は書き換えられない' do
      expect { doc(macro).remove(['sequence', 0, 'action']) }
        .to raise_error(Cornix::Storage::EditNotLocal) { |e| expect(e.reason).to eq(:shared_line) }
      expect { doc("k: [a,\n  b]\n").remove(['k', 0]) }
        .to raise_error(Cornix::Storage::EditNotLocal) { |e| expect(e.reason).to eq(:flow_insert) }
    end

    it 'アンカーとエイリアスは書き換えられない' do
      expect { doc("a: &x [1, 2]\nb: *x\n").remove(['a', 0]) }
        .to raise_error(Cornix::Storage::EditNotLocal) { |e| expect(e.reason).to eq(:anchor) }
    end
  end

  describe '#insert_item' do
    it 'ブロック形式の並びには、同じ字下げの「- 値」の行を index の前に足す（並びの長さなら末尾）' do
      expect(inserted(macro, ['sequence', 0, 'keys'], 0, ',')).to eq(macro.sub("  - KC_A\n", "  - \",\"\n  - KC_A\n"))
      expect(inserted(macro, ['sequence', 0, 'keys'], 2, 'KC_D')).to eq(macro.sub("# B のコメント\n", "# B のコメント\n  - KC_D\n"))
    end

    it 'Hash の値は「- 最初の項目」と字下げした残りの項目（中の並びはフロー表記）' do
      step = { 'action' => 'tap', 'keys' => %w[KC_X KC_Y] }
      expect(inserted(macro, ['sequence'], 1, step))
        .to eq(macro.sub("# 手順 1 の前", "- action: tap\n  keys: [KC_X, KC_Y]\n# 手順 1 の前"))
      expect(inserted(macro, ['sequence'], 3, { 'action' => 'text', 'content' => 'a: b' }))
        .to eq("#{macro}- action: text\n  content: \"a: b\"\n")
    end

    it '1 つの値で書いた場所は、フロー表記の並びに置き換える' do
      expect(inserted(macro, ['sequence', 1, 'keys'], 1, 'KC_D')).to eq(macro.sub('keys: KC_C', 'keys: [KC_C, KC_D]'))
      expect(inserted(macro, ['sequence', 1, 'keys'], 0, 'KC_D')).to eq(macro.sub('keys: KC_C', 'keys: [KC_D, KC_C]'))
    end

    it '値のない場所は要素 1 つのフロー表記の並びにする' do
      expect(inserted("trigger_keys:\noutput_key: X\n", ['trigger_keys'], 0, 'KC_A')).to eq("trigger_keys: [KC_A]\noutput_key: X\n")
      expect(inserted("trigger_keys: ~\n", ['trigger_keys'], 0, 'KC_A')).to eq("trigger_keys: [KC_A]\n")
    end

    it 'フロー表記の並びは 1 行で書き直す。複数行なら書き換えられない' do
      expect(inserted("k: [KC_A, KC_B]\n", ['k'], 1, ',')).to eq("k: [KC_A, \",\", KC_B]\n")
      expect { doc("k: [a,\n  b]\n").insert_item(['k'], 0, 'c') }
        .to raise_error(Cornix::Storage::EditNotLocal) { |e| expect(e.reason).to eq(:flow_insert) }
    end
  end

  describe '#move_item' do
    it 'ブロック形式の並びは、要素の行（前の要素とのあいだのコメントの行を含む）ごと動かす' do
      expect(moved(macro, ['sequence'], 0, 2)).to eq(<<~YAML)
        ---
        index: 0
        name: M
        sequence:
        # 手順 1 の前のコメント
        - action: down
          keys: KC_C
        - action: delay
          duration: 10
        - action: tap
          keys:
          - KC_A
          - KC_B # B のコメント
      YAML
      expect(moved(macro, ['sequence', 0, 'keys'], 1, 0)).to eq(macro.sub("  - KC_A\n  - KC_B # B のコメント\n", "  - KC_B # B のコメント\n  - KC_A\n"))
    end

    it '書き換えは変わった行だけ' do
      edits = doc(macro).move_item(['sequence', 0, 'keys'], 1, 0)
      expect(edits.map { |e| [e.range.start_line, e.range.end_line] }).to all(satisfy { |s, e| s >= 6 && e <= 8 })
    end

    it 'フロー表記の並びは 1 行で書き直す。同じ位置なら []' do
      expect(moved("k: [a, b, c]\n", ['k'], 2, 0)).to eq("k: [c, a, b]\n")
      expect(doc("k: [a, b]\n").move_item(['k'], 1, 1)).to eq([])
      expect(doc("k: a\n").move_item(['k'], 0, 0)).to eq([])
    end
  end

  describe '#set_note と #remove_note' do
    it '注記のない形は { key: 値, note: 注記 } にする（もとの表記はそのまま）' do
      expect(apply("tab: 'Q'\n", doc("tab: 'Q'\n").set_note(['tab'], 'メモ'))).to eq("tab: { key: 'Q', note: メモ }\n")
      expect(apply("r: { tab: Q }\n", doc("r: { tab: Q }\n").set_note(%w[r tab], 'a, b'))).to eq("r: { tab: { key: Q, note: \"a, b\" } }\n")
    end

    it '注記付きの形は note の値だけを置き換え、note がなければ足す' do
      text = "tab: { key: Q, note: 古い } # c\n"
      expect(apply(text, doc(text).set_note(['tab'], '新しい'))).to eq("tab: { key: Q, note: 新しい } # c\n")
      expect(apply("tab: { key: Q }\n", doc("tab: { key: Q }\n").set_note(['tab'], 'x'))).to eq("tab: { key: Q, note: x }\n")
      expect(apply("tab:\n  key: Q\n", doc("tab:\n  key: Q\n").set_note(['tab'], 'x'))).to eq("tab:\n  key: Q\n  note: x\n")
    end

    it '注記を消すと、1 行のフロー表記は key の値だけに、ブロック形式は note の行を消す' do
      expect(apply("tab: { key: Q, note: x }\n", doc("tab: { key: Q, note: x }\n").remove_note(['tab']))).to eq("tab: Q\n")
      text = "tab:\n  key: Q\n  note: x\n"
      expect(apply(text, doc(text).remove_note(['tab']))).to eq("tab:\n  key: Q\n")
      expect(doc("tab: Q\n").remove_note(['tab'])).to eq([])
    end

    it '割り当てがなければ ArgumentError' do
      expect { doc("tab:\n").set_note(['tab'], 'x') }.to raise_error(ArgumentError)
    end
  end
end
