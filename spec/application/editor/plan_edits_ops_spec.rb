# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'

# v0.2 の Change（protocol.md の 12.3）: op（remove / insert / move）と field: :note、マクロ・タップダンス・コンボ・
# ショートカット・説明の宛先。書き換えを compile と照らすのは plan_edits_compile_spec.rb
RSpec.describe Cornix::Application::Editor::PlanEdits do
  around do |example|
    Dir.mktmpdir('cornix-plan-edits-ops') do |dir|
      @root = File.realpath(dir)
      FileUtils.cp_r(File.join(__dir__, '../../fixtures/test_config'), File.join(@root, 'profile'))
      example.run
    end
  end

  let(:workbench) { Cornix::Application::Editor::Workbench.new(root: @root) }
  let(:opened) { workbench.open('profile') }
  let(:layer) { 'layers/0_layer_0.yaml' }
  let(:macro) { 'macros/00_macro.yaml' }
  let(:tap_dance) { 'tap_dance/00_tap_dance.yaml' }
  let(:combo) { 'combos/00_combo.yaml' }

  def path(rel) = File.join(@root, 'profile', rel)
  def read(rel) = File.read(path(rel))
  def write(rel, text) = File.write(path(rel), text)
  def version(rel) = File.exist?(path(rel)) ? Cornix::Storage::FileVersion.read(path(rel)) : nil

  def plan(changes, base_versions: changes.map(&:file).uniq.to_h { |f| [f, version(f)] })
    described_class.new(workbench).call(opened.id, base_versions: base_versions, changes: changes)
  end

  def change(file, path, **options) = described_class::Change.new(file: file, path: path, **options)

  def applied(result, file)
    entry = result[:files].find { |f| f[:file] == file } or return read(file)
    edits = entry[:edits].map do |e|
      r = e[:range]
      range = Cornix::Storage::TextRange.new(start_line: r[:start][:line], start_character: r[:start][:character],
                                             end_line: r[:end][:line], end_character: r[:end][:character])
      Cornix::Storage::TextEdit.new(range: range, new_text: e[:newText])
    end
    Cornix::Storage::TextEdit.apply(entry[:create] ? '' : read(file), edits)
  end

  def invalid_field(changes)
    plan(changes)
  rescue described_class::InvalidChange => e
    e.field
  else
    raise 'InvalidChange になりませんでした'
  end

  describe 'レイヤー' do
    it 'キーの remove は行を消し、グループの見出しは残す。書いていないキーの remove は何もしない' do
      write(layer, read(layer).sub("    row3:\n      lctrl: CapsLock\n", "    row3:\n      lctrl: CapsLock # c\n"))
      text = read(layer)
      result = plan([change(layer, %w[mapping left_hand row0 tab], op: :remove)])
      expect(applied(result, layer)).to eq(text.sub("      tab: Tab\n", ''))
      expect(result[:diagnostics]).to eq([])

      write(layer, text.sub("      tab: Tab\n", ''))
      expect(plan([change(layer, %w[mapping left_hand row0 tab], op: :remove)])[:files]).to eq([])
    end

    it 'グループのキーをすべて消しても見出し（row0:）は残り、構造の問題にならない' do
      symbols = %w[tab Q W E R T]
      result = plan(symbols.map { |s| change(layer, ['mapping', 'left_hand', 'row0', s], op: :remove) })
      expect(applied(result, layer)).to include("    row0:\n    row1:\n")
      expect(result[:diagnostics]).to eq([])
    end

    it '注記を書く・消す（field: :note）。注記のない形は { key:, note: } にする' do
      result = plan([change(layer, %w[mapping left_hand row0 tab], field: :note, value: 'メモ'),
                     change(layer, %w[mapping encoders left push], field: :note, value: '押す')])
      text = applied(result, layer)
      expect(text).to include('tab: { key: Tab, note: メモ }')
      expect(text).to match(/push: \{ key: \S+, note: 押す \}/)

      write(layer, text)
      result = plan([change(layer, %w[mapping left_hand row0 tab], op: :remove, field: :note)])
      expect(applied(result, layer)).to include("      tab: Tab\n")
    end

    it '割り当てのない場所に注記だけは書かない（changes[i].address）。前の変更で割り当てれば書ける' do
      write(layer, read(layer).sub("      tab: Tab\n", ''))
      expect(invalid_field([change(layer, %w[mapping left_hand row0 tab], field: :note, value: 'x')])).to eq('changes[0].address')
      result = plan([change(layer, %w[mapping left_hand row0 tab], value: 'Tab'),
                     change(layer, %w[mapping left_hand row0 tab], field: :note, value: 'x')])
      expect(applied(result, layer)).to include("    row0:\n      tab: { key: Tab, note: x }\n      Q: Q\n")
    end

    it '説明を書く・消す。名前は宛先にしない（番号は v0.5 で宛先にした。下の「番号」）' do
      result = plan([change(layer, ['description'], value: '基本')])
      expect(applied(result, layer)).to include("description: '基本'\n")
      result = plan([change(layer, ['description'], op: :remove)])
      expect(applied(result, layer)).not_to include('description')
      expect(invalid_field([change(layer, ['name'], value: 'X')])).to eq('changes[0].address')
      expect(invalid_field([change(layer, ['index'], value: '1')])).to eq('changes[0].value')
    end

    it 'その宛先でできない op は changes[i].address' do
      expect(invalid_field([change(layer, %w[mapping left_hand row0], op: :insert, index: 0, value: 'Q')])).to eq('changes[0].address')
      expect(invalid_field([change(layer, %w[mapping left_hand row0 tab], op: :move, from: 0, to: 0)])).to eq('changes[0].address')
    end
  end

  describe 'マクロ' do
    it '手順の挿入（MacroStepValue）・キーの挿入と削除。並びの位置は前の変更を当てたあとで数える' do
      result = plan([change(macro, ['sequence'], op: :insert, index: 0, value: { 'action' => 'delay', 'duration' => 30 }),
                     change(macro, ['sequence', 1, 'keys'], op: :insert, index: 3, value: 'KC_RIGHT'),
                     change(macro, ['sequence', 1, 'keys', 0], op: :remove),
                     change(macro, ['sequence', 0, 'duration'], value: 40)])
      expect(applied(result, macro)).to eq(read(macro).sub("sequence:\n- action: tap\n  keys:\n  - KC_LBRACKET\n",
                                                           "sequence:\n- action: delay\n  duration: 40\n- action: tap\n  keys:\n") +
                                           "\n  - KC_RIGHT")
    end

    it '手順を消して動かす。手順が 0 個になれば構造の error（書き換えは作る）' do
      result = plan([change('macros/02_macro.yaml', ['sequence'], op: :move, from: 3, to: 0),
                     change('macros/02_macro.yaml', ['sequence', 1], op: :remove)])
      expect(applied(result, 'macros/02_macro.yaml'))
        .to eq("---\nindex: 2\nname: Macro 2\ndescription: ''\nsequence:\n- action: tap\n  keys:\n  - KC_RIGHT\n" \
               "- action: tap\n  keys:\n  - KC_C\n- action: up\n  keys:\n  - KC_LGUI")

      result = plan([change(macro, ['sequence', 0], op: :remove)])
      expect(result[:diagnostics]).to contain_exactly(include(severity: 'error', source: 'structure'))
    end

    it '1 つの値で書いた keys は ["sequence", i, "keys"] で書き換え、挿入はフロー表記の並びにする' do
      write(macro, read(macro).sub("  keys:\n  - KC_LBRACKET\n  - KC_RBRACKET\n  - KC_LEFT", '  keys: KC_A'))
      result = plan([change(macro, ['sequence', 0, 'keys'], value: 'KC_B')])
      expect(applied(result, macro)).to end_with('keys: KC_B')
      result = plan([change(macro, ['sequence', 0, 'keys'], op: :insert, index: 1, value: 'KC_C'),
                     change(macro, ['sequence', 0, 'keys', 1], value: 'KC_D')])
      expect(applied(result, macro)).to end_with('keys: [KC_A, KC_D]')
    end

    it '並びで書いた keys を ["sequence", i, "keys"] で set すると changes[i].address' do
      expect(invalid_field([change(macro, ['sequence', 0, 'keys'], value: 'KC_A')])).to eq('changes[0].address')
    end

    it '位置の誤りは changes[i].address / index / from / to' do
      expect(invalid_field([change(macro, ['sequence', 5], op: :remove)])).to eq('changes[0].address')
      expect(invalid_field([change(macro, ['sequence', 0, 'keys', 3], value: 'KC_A')])).to eq('changes[0].address')
      expect(invalid_field([change(macro, ['sequence', 0, 'duration'], value: 10)])).to eq('changes[0].address')
      expect(invalid_field([change(macro, ['sequence'], op: :insert, index: 2, value: { 'action' => 'delay', 'duration' => 1 })]))
        .to eq('changes[0].index')
      expect(invalid_field([change(macro, ['sequence', 0, 'keys'], op: :move, from: 3, to: 0)])).to eq('changes[0].from')
      expect(invalid_field([change(macro, ['sequence', 0, 'keys'], op: :move, from: 0, to: -1)])).to eq('changes[0].to')
    end

    it 'MacroStepValue とキーの値の型が違えば changes[i].value' do
      [{ 'action' => 'tap', 'keys' => 'KC_A' }, { 'action' => 'delay', 'duration' => '1' }, { 'action' => 'beep' },
       { 'action' => 'text', 'content' => 'a', 'keys' => [] }, 'KC_A'].each do |value|
        expect(invalid_field([change(macro, ['sequence'], op: :insert, index: 0, value: value)])).to eq('changes[0].value')
      end
      expect(invalid_field([change(macro, ['sequence', 0, 'keys'], op: :insert, index: 0, value: { 'a' => 1 })]))
        .to eq('changes[0].value')
    end

    it 'preset: のマクロは preset と説明だけ' do
      write(macro, "---\nindex: 0\npreset: 'macOS:システム:ウィンドウキャプチャ'\n")
      result = plan([change(macro, ['preset'], value: 'macOS:システム:画面全体のキャプチャ')])
      expect(applied(result, macro)).to include("preset: 'macOS:システム:画面全体のキャプチャ'")
      expect(invalid_field([change(macro, ['sequence'], op: :insert, index: 0, value: { 'action' => 'tap', 'keys' => ['KC_A'] })]))
        .to eq('changes[0].address')
    end

    it 'マクロのキーには注記を書けない（changes[i].field）' do
      expect(invalid_field([change(macro, ['sequence', 0, 'keys', 0], field: :note, value: 'x')])).to eq('changes[0].field')
    end
  end

  describe 'タップダンス' do
    it '上の階層に書いたファイルは ["on_tap"] を指し、actions: の下の Address は指せない' do
      result = plan([change(tap_dance, ['on_double_tap'], value: 'KC_A'), change(tap_dance, ['on_tap'], field: :note, value: '注記'),
                     change(tap_dance, ['tapping_term'], value: 300)])
      expect(applied(result, tap_dance))
        .to eq(read(tap_dance).sub('on_double_tap: KC_NO', 'on_double_tap: KC_A').sub('on_tap: OSL(4)', 'on_tap: { key: OSL(4), note: 注記 }')
                              .sub('tapping_term: 200', 'tapping_term: 300'))
      expect(invalid_field([change(tap_dance, %w[actions on_tap], value: 'KC_A')])).to eq('changes[0].address')
    end

    it '動作をどちらにも書いていなければ actions: の下に足す。tapping_term を消す' do
      write(tap_dance, "---\nindex: 0\nname: TapDance 0\ntapping_term: 200\n")
      result = plan([change(tap_dance, %w[actions on_hold], value: 'MO(1)'), change(tap_dance, ['tapping_term'], op: :remove)])
      expect(applied(result, tap_dance)).to eq("---\nindex: 0\nname: TapDance 0\nactions:\n  on_hold: MO(1)\n")
    end

    it 'tapping_term は整数' do
      expect(invalid_field([change(tap_dance, ['tapping_term'], value: '200')])).to eq('changes[0].value')
    end
  end

  describe 'コンボ' do
    it 'trigger_keys の挿入・移動・削除と output_key の注記' do
      result = plan([change(combo, ['trigger_keys', 3], op: :remove), change(combo, ['trigger_keys', 2], op: :remove),
                     change(combo, ['trigger_keys'], op: :insert, index: 2, value: 'KC_G'),
                     change(combo, ['trigger_keys'], op: :move, from: 2, to: 0),
                     change(combo, ['output_key'], field: :note, value: '左角括弧')])
      expect(applied(result, combo)).to eq(read(combo).sub("- KC_D\n- KC_F\n- KC_NO\n- KC_NO\n", "- KC_G\n- KC_D\n- KC_F\n")
                                                     .sub('output_key: KC_LBRACKET', 'output_key: { key: KC_LBRACKET, note: 左角括弧 }'))
    end

    it 'ブロック形式の要素をすべて消した（値なしの）trigger_keys にも足せる。書いていなければ指せない' do
      changes = [change(combo, ['trigger_keys', 0], op: :remove)] * 4
      result = plan(changes + [change(combo, ['trigger_keys'], op: :insert, index: 0, value: 'KC_A')])
      expect(applied(result, combo)).to include("trigger_keys: [KC_A]\noutput_key:")

      write(combo, read(combo).sub("trigger_keys:\n- KC_D\n- KC_F\n- KC_NO\n- KC_NO\n", ''))
      expect(invalid_field([change(combo, ['trigger_keys'], op: :insert, index: 0, value: 'KC_A')])).to eq('changes[0].address')
    end

    it 'output_key は消せない。trigger_keys の要素に注記は書けない' do
      expect(invalid_field([change(combo, ['output_key'], op: :remove)])).to eq('changes[0].address')
      expect(invalid_field([change(combo, ['trigger_keys', 0], field: :note, value: 'x')])).to eq('changes[0].field')
    end

    it '複数行のフロー表記の並びへの挿入は NotLocal（flowInsert）' do
      write(combo, read(combo).sub("trigger_keys:\n- KC_D\n- KC_F\n- KC_NO\n- KC_NO\n", "trigger_keys: [KC_D,\n  KC_F]\n"))
      expect { plan([change(combo, ['trigger_keys'], op: :insert, index: 0, value: 'KC_A')]) }
        .to raise_error(described_class::NotLocal) { |e| expect([e.reason, e.address]).to eq(['flowInsert', { file: combo, path: ['trigger_keys'] }]) }
    end
  end

  describe 'ショートカット' do
    before { write('shortcuts.yaml', "shortcuts:\n  前のタブへ: Command + Shift + [ # コメント\n") }

    it 'いまある名前の値を書き換える。消すこと・注記は指せない' do
      result = plan([change('shortcuts.yaml', %w[shortcuts 前のタブへ], value: 'Ctrl + Tab')])
      expect(applied(result, 'shortcuts.yaml')).to eq("shortcuts:\n  前のタブへ: Ctrl + Tab # コメント\n")
      expect(invalid_field([change('shortcuts.yaml', %w[shortcuts 前のタブへ], op: :remove)])).to eq('changes[0].address')
      expect(invalid_field([change('shortcuts.yaml', %w[shortcuts 前のタブへ], field: :note, value: 'x')])).to eq('changes[0].field')
    end
  end

  describe 'ショートカットの行の追加（v0.5。protocol.md の 15.2）' do
    it 'まだない名前の set は shortcuts: の末尾に行を足し、名前の決まりに合わなければ changes[i].address' do
      write('shortcuts.yaml', "shortcuts:\n  前のタブへ: Command + Shift + [ # コメント\n")
      result = plan([change('shortcuts.yaml', %w[shortcuts 次のタブへ], value: 'Tab'),
                     change('shortcuts.yaml', %w[shortcuts 次のタブへ], value: 'Command + Shift + ]')])
      expect(applied(result, 'shortcuts.yaml'))
        .to eq("shortcuts:\n  前のタブへ: Command + Shift + [ # コメント\n  次のタブへ: Command + Shift + ]\n")
      ['', ' a', "a\nb"].each do |name|
        expect(invalid_field([change('shortcuts.yaml', ['shortcuts', name], value: 'Tab')])).to eq('changes[0].address')
      end
    end

    it 'shortcuts.yaml がなければ create: true で作る' do
      result = plan([change('shortcuts.yaml', %w[shortcuts a], value: 'KC_A')], base_versions: { 'shortcuts.yaml' => nil })
      expect(result[:files].first).to include(file: 'shortcuts.yaml', baseVersion: nil, create: true)
      expect(applied(result, 'shortcuts.yaml')).to eq("shortcuts:\n  a: KC_A\n")
    end
  end

  describe '番号（["index"]。v0.5。protocol.md の 15.2）' do
    it '行があれば値を置き換え、値が空なら書き、なければ name: の行のすぐ後に足す。remove は行を消す' do
      result = plan([change(macro, ['index'], value: 12)])
      expect(applied(result, macro)).to start_with("---\nindex: 12\nname: Macro 0\n")
      write(macro, read(macro).sub("index: 0\n", "index:\n"))
      expect(applied(plan([change(macro, ['index'], value: 3)]), macro)).to start_with("---\nindex: 3\nname: Macro 0\n")
      write(macro, read(macro).sub("index:\n", ''))
      expect(applied(plan([change(macro, ['index'], value: 3)]), macro)).to start_with("---\nname: Macro 0\nindex: 3\ndescription: ''\n")
      write(macro, read(macro).sub("name: Macro 0\n", ''))
      expect(applied(plan([change(macro, ['index'], value: 3)]), macro)).to start_with("---\nindex: 3\ndescription: ''\n")
      result = plan([change(layer, ['index'], op: :remove)])
      expect(applied(result, layer)).not_to match(/^index:/)
      expect(plan([change(macro, ['index'], op: :remove)])[:files]).to eq([])
    end

    it '値は 0 以上の整数（範囲と重なりは意味検証の error で知らせる）' do
      ['1', -1, 1.5].each { |value| expect(invalid_field([change(macro, ['index'], value: value)])).to eq('changes[0].value') }
      result = plan([change(macro, ['index'], value: 1)])
      expect(result[:diagnostics]).to include(include(severity: 'error', source: 'semantic'))
    end

    it '番号を書いた未使用のファイルは使っている項目として、消したファイルは未使用として検証する' do
      write('macros/spare.yaml', "name: Spare\nsequence: [{ action: tap, keys: [Nope] }]\n")
      expect(plan([])[:diagnostics]).to contain_exactly(include(severity: 'warning', source: 'structure'))
      result = plan([change('macros/spare.yaml', ['index'], value: 12)])
      expect(result[:diagnostics]).to contain_exactly(include(severity: 'error', source: 'structure'))
      result = plan([change('macros/spare.yaml', ['sequence', 0, 'keys', 0], value: 'KC_B'), change('macros/spare.yaml', ['index'], value: 12)])
      expect(result[:diagnostics]).to eq([])
    end
  end

  it 'profile/validate も同じ宛先と書き換えで検証する（trigger_keys を空にすると構造の error）' do
    changes = [change(combo, ['trigger_keys', 0], op: :remove)] * 4
    result = Cornix::Application::Editor::ValidateDraft.new(workbench)
                                                       .call(opened.id, base_versions: { combo => version(combo) }, changes: changes)
    expect(result[:diagnostics]).to contain_exactly(include(severity: 'error', source: 'structure'))
  end
end
