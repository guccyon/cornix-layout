# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'

# v0.5 の use / unuse / setIndex と create（shortcut）（protocol.md の 15.3）。応答の形の約束は spec/fixtures/protocol/profile_plan_item_edit の
# use_* / unuse_* / set_index_* / create_shortcut_*。ここでは番号の決め方・未保存の変更の当て方・参照の書き換えと compile の結果を確かめる
RSpec.describe Cornix::Application::Editor::ItemEdits do
  around do |example|
    Dir.mktmpdir('cornix-indexing') do |dir|
      @root = File.realpath(dir)
      FileUtils.cp_r(File.join(__dir__, '../../../fixtures', 'test_config'), File.join(@root, 'profile'))
      example.run
    end
  end

  let(:workbench) { Cornix::Application::Editor::Workbench.new(root: @root) }
  let(:opened) { workbench.open('profile') }
  let(:plan_edits) { Cornix::Application::Editor::PlanEdits }
  let(:change) { plan_edits::Change }

  def path(rel) = File.join(@root, 'profile', rel)
  def read(rel) = File.read(path(rel))
  def write(rel, text) = FileUtils.mkdir_p(File.dirname(path(rel))).then { File.write(path(rel), text) }
  def reading = Cornix::Application::Editor::ProfileReading.read(opened.env)

  def plan(changes: [], **fields)
    described_class.new(workbench).call(opened.id, base_versions: reading.files, edit: described_class::Edit.new(**fields),
                                                   changes: changes)
  end

  # 結果の changes（protocol の Hash）を PlanEdits::Change に戻す
  def to_changes(list)
    list.map do |c|
      change.new(file: c[:address][:file], path: c[:address][:path], op: (c[:op] || 'set').to_sym, value: c[:value])
    end
  end

  # changes を当てたあとの中身で読み直したもの
  def applied(changes)
    plan_edits::Draft.new(reading, opened.env.settings_catalog)
                     .apply(changes.map(&:file).uniq.to_h { |f| [f, reading.files[f]] }, changes)
  end

  def index_change(file, value) = change.new(file: file, path: ['index'], value: value)

  it 'ファイルは書かず、files は []（未保存の変更に積む changes を返す）' do
    before = Dir.glob(path('**/*')).sort.to_h { |f| [f, File.file?(f) ? File.read(f) : nil] }
    result = plan(op: 'unuse', kind: 'macro', file: 'macros/11_macro.yaml')
    expect(result[:files]).to eq([])
    expect(result[:changes]).to eq([{ op: 'remove', address: { file: 'macros/11_macro.yaml', path: ['index'] } }])
    expect(Dir.glob(path('**/*')).sort.to_h { |f| [f, File.file?(f) ? File.read(f) : nil] }).to eq(before)
  end

  describe 'use' do
    before { write('macros/spare.yaml', "name: Spare\nsequence: [{ action: tap, keys: [KC_A] }]\n") }

    it '使っているいちばん大きい番号の次（test_config のマクロは 0〜8・10・11）。未保存の変更を当てた状態で決める' do
      expect(plan(op: 'use', kind: 'macro', file: 'macros/spare.yaml')[:changes])
        .to eq([{ address: { file: 'macros/spare.yaml', path: ['index'] }, value: 12 }])
      write('macros/spare2.yaml', "name: Spare 2\nsequence: [{ action: tap, keys: [KC_B] }]\n")
      result = plan(op: 'use', kind: 'macro', file: 'macros/spare2.yaml', changes: [index_change('macros/spare.yaml', 12)])
      expect(result[:changes]).to eq([{ address: { file: 'macros/spare2.yaml', path: ['index'] }, value: 13 }])
    end

    it '次が上限なら空いているいちばん小さい番号、何も使っていなければ 0' do
      result = plan(op: 'use', kind: 'macro', file: 'macros/spare.yaml', changes: [index_change('macros/11_macro.yaml', 31)])
      expect(result[:changes].first[:value]).to eq(9)
      Dir.glob(path('combos/*')).each { |f| File.write(f, File.read(f).sub(/^index: \d+\n/, '')) }
      expect(plan(op: 'use', kind: 'combo', file: 'combos/02_combo.yaml')[:changes].first[:value]).to eq(0)
    end

    it '空きがなければ field "edit"、使っている項目・ないファイル・種類の違うファイルは field "edit.file"' do
      write('layers/spare.yaml', read('layers/1_layer_1.yaml').sub(/^index: 1\n/, ''))
      expect { plan(op: 'use', kind: 'layer', file: 'layers/spare.yaml') }
        .to raise_error(plan_edits::InvalidChange) { |e| expect(e.field).to eq('edit') }
      [['macro', 'macros/00_macro.yaml'], ['macro', 'macros/none.yaml'], ['tapDance', 'macros/spare.yaml']].each do |kind, file|
        expect { plan(op: 'use', kind: kind, file: file) }
          .to raise_error(plan_edits::InvalidChange) { |e| expect(e.field).to eq('edit.file') }
      end
    end

    it '取り出した項目は使っている項目として検証する（diagnostics）' do
      write('macros/spare.yaml', "name: Macro 0\nsequence: [{ action: tap, keys: [KC_A] }]\n")
      result = plan(op: 'use', kind: 'macro', file: 'macros/spare.yaml')
      expect(result[:diagnostics]).to include(include(severity: 'error', source: 'semantic', message: include('Macro 0')))
    end
  end

  describe 'unuse' do
    it 'references は壊れる参照（番号の参照も。そのファイルの中は入れない）。レイヤーはレイヤー操作' do
      result = plan(op: 'unuse', kind: 'macro', file: 'macros/02_macro.yaml')
      expect(result[:references]).to include({ file: 'tap_dance/02_tap_dance.yaml', path: ['on_hold'] })
      result = plan(op: 'unuse', kind: 'layer', file: 'layers/1_layer_1.yaml')
      expect(result[:changes]).to eq([{ op: 'remove', address: { file: 'layers/1_layer_1.yaml', path: ['index'] } }])
      expect(result[:references]).to include({ file: 'tap_dance/00_tap_dance.yaml', path: ['on_hold'] })
      expect(result[:references].map { |a| a[:file] }).not_to include('layers/1_layer_1.yaml')
    end

    it '未使用の項目（未保存の変更で未使用にしたものも）は field "edit.file"' do
      remove = change.new(file: 'combos/00_combo.yaml', path: ['index'], op: :remove)
      expect { plan(op: 'unuse', kind: 'combo', file: 'combos/00_combo.yaml', changes: [remove]) }
        .to raise_error(plan_edits::InvalidChange) { |e| expect(e.field).to eq('edit.file') }
    end
  end

  describe '未使用の項目を名前で指す欄（読めない値）が残っているとき' do
    # タップダンス 0 がマクロ 11 を名前で指したまま、マクロ 11 を未使用にした（保存したあとの）状態
    before do
      write('tap_dance/00_tap_dance.yaml', read('tap_dance/00_tap_dance.yaml').sub('on_double_tap: KC_NO', "on_double_tap: Macro('Macro 11')"))
      write('macros/11_macro.yaml', read('macros/11_macro.yaml').sub(/^index: 11\n/, ''))
    end

    it '画面には出せるが読めない値がある' do
      expect([reading.ok?, reading.complete?]).to eq([true, false])
    end

    it '取り出す・未使用にする・番号の変更・ショートカットの追加は止めない。取り出せば参照も読める' do
      result = plan(op: 'use', kind: 'macro', file: 'macros/11_macro.yaml')
      expect(result[:changes]).to eq([{ address: { file: 'macros/11_macro.yaml', path: ['index'] }, value: 11 }])
      expect(applied(to_changes(result[:changes])).reading.complete?).to be(true)
      expect(plan(op: 'unuse', kind: 'tapDance', file: 'tap_dance/00_tap_dance.yaml')[:changes])
        .to eq([{ op: 'remove', address: { file: 'tap_dance/00_tap_dance.yaml', path: ['index'] } }])
      expect(plan(op: 'setIndex', kind: 'macro', file: 'macros/10_macro.yaml', index: 20)[:changes])
        .to include({ address: { file: 'macros/10_macro.yaml', path: ['index'] }, value: 20 })
      expect(plan(op: 'create', kind: 'shortcut', name: 'S', value: 'KC_A')[:changes].size).to eq(1)
    end
  end

  describe 'setIndex' do
    it 'マクロの入れ替えは番号の参照を表記の形のまま両方向に書き換え、compile すると各キーは同じ中身のマクロを指す' do
      write('layers/1_layer_1.yaml', read('layers/1_layer_1.yaml').sub(/^(\s+)tab: .*$/, "\\1tab: Macro( 1 )"))
      result = plan(op: 'setIndex', kind: 'macro', file: 'macros/00_macro.yaml', index: 1)
      expect(result[:changes].first(2)).to eq([{ address: { file: 'macros/00_macro.yaml', path: ['index'] }, value: 1 },
                                               { address: { file: 'macros/01_macro.yaml', path: ['index'] }, value: 0 }])
      rewritten = result[:changes].drop(2).to_h { |c| [c[:address], c[:value]] }
      expect(rewritten).to include({ file: 'layers/2_layer_2.yaml', path: %w[mapping left_hand row1 A] } => 'M1',
                                   { file: 'layers/2_layer_2.yaml', path: %w[mapping left_hand row1 S] } => 'M0',
                                   { file: 'layers/1_layer_1.yaml', path: %w[mapping left_hand row0 tab] } => 'Macro( 0 )')
      expect(result[:references]).to eq(rewritten.keys)

      env = opened.env
      before = env.mapper.to_image(reading.profile)
      after = env.mapper.to_image(applied(to_changes(result[:changes])).reading.profile)
      expect(after.macros.values_at(0, 1)).to eq(before.macros.values_at(1, 0))
      macro_of = ->(image, code) { (0x7700..0x771F).cover?(code) ? image.macros[code - 0x7700] : code }
      before.layers.each_with_index do |layer, l|
        layer.each_with_index do |row, r|
          row.each_with_index { |code, c| expect(macro_of.call(after, after.layers[l][r][c])).to eq(macro_of.call(before, code)) }
        end
      end
    end

    it '名前の参照は書き換えない（名前で引くので追従する）' do
      write('layers/1_layer_1.yaml', read('layers/1_layer_1.yaml').sub(/^(\s+)tab: .*$/, "\\1tab: Macro('Macro 0')"))
      result = plan(op: 'setIndex', kind: 'macro', file: 'macros/00_macro.yaml', index: 20)
      expect(result[:changes].map { |c| c[:address][:file] }).not_to include('layers/1_layer_1.yaml')
      expect(result[:changes].first).to eq({ address: { file: 'macros/00_macro.yaml', path: ['index'] }, value: 20 })
      expect(result[:changes].size).to eq(2) # index と 2_layer_2 の M0
    end

    it 'タップダンスは TD(n) を書き換え、レイヤーは参照を書き換えない（references は []）' do
      result = plan(op: 'setIndex', kind: 'tapDance', file: 'tap_dance/02_tap_dance.yaml', index: 9)
      expect(result[:changes]).to include({ address: { file: 'layers/2_layer_2.yaml', path: %w[mapping left_hand row2 C] }, value: 'TD(9)' })
      result = plan(op: 'setIndex', kind: 'layer', file: 'layers/1_layer_1.yaml', index: 4)
      expect(result[:changes]).to eq([{ address: { file: 'layers/1_layer_1.yaml', path: ['index'] }, value: 4 },
                                      { address: { file: 'layers/4_layer_4.yaml', path: ['index'] }, value: 1 }])
      expect(result[:references]).to eq([])
    end

    it '未保存の変更で書いた番号の参照も書き換える' do
      key = change.new(file: 'layers/1_layer_1.yaml', path: %w[mapping left_hand row0 tab], value: 'TapDance(0)')
      result = plan(op: 'setIndex', kind: 'tapDance', file: 'tap_dance/00_tap_dance.yaml', index: 5, changes: [key])
      expect(result[:changes]).to include({ address: { file: key.file, path: key.path }, value: 'TapDance(5)' })
    end

    it '範囲の外・今と同じ番号は field "edit.index"、未使用の項目は "edit.file"' do
      [32, -1, 0].each do |index|
        expect { plan(op: 'setIndex', kind: 'macro', file: 'macros/00_macro.yaml', index: index) }
          .to raise_error(plan_edits::InvalidChange) { |e| expect(e.field).to eq('edit.index') }
      end
      write('macros/spare.yaml', "name: Spare\nsequence: [{ action: tap, keys: [KC_A] }]\n")
      expect { plan(op: 'setIndex', kind: 'macro', file: 'macros/spare.yaml', index: 20) }
        .to raise_error(plan_edits::InvalidChange) { |e| expect(e.field).to eq('edit.file') }
    end

    it '書き換えられない番号の参照（YAML の整数で書いた 16bit 値）があれば Unverified' do
      write('layers/1_layer_1.yaml', read('layers/1_layer_1.yaml').sub(/^(\s+)tab: .*$/, "\\1tab: #{0x7700}"))
      expect { plan(op: 'setIndex', kind: 'macro', file: 'macros/00_macro.yaml', index: 20) }
        .to raise_error(described_class::Unverified) { |e| expect(e.address).to eq({ file: 'macros/00_macro.yaml', path: ['index'] }) }
    end
  end

  describe 'NumberedReference' do
    let(:codec) { opened.env.notation.codec }
    let(:macro) { Cornix::Domain::Keycode::MacroCall.new(index: 5) }

    it '番号で書いた表記だけを、形を保って書き換える' do
      rewrite = ->(text, keycode = macro) { described_class::NumberedReference.rewrite(text, keycode, codec) }
      expect(rewrite.call('Macro(3)')).to eq('Macro(5)')
      expect(rewrite.call('M3')).to eq('M5')
      expect(rewrite.call('0x7703')).to eq('0x7705')
      expect(rewrite.call('0x770a')).to eq('0x7705')
      expect(rewrite.call("Macro('Copy')")).to be_nil
      td = Cornix::Domain::Keycode::TapDanceCall.new(index: 12)
      expect(rewrite.call('TD(2)', td)).to eq('TD(12)')
      expect(rewrite.call('TapDance( 2 )', td)).to eq('TapDance( 12 )')
      expect(rewrite.call('0x5702', td)).to eq('0x570C')
    end
  end

  describe 'create（shortcut）' do
    it '["shortcuts", 名前] の set を返し、未保存の変更の名前とも重ならない' do
      result = plan(op: 'create', kind: 'shortcut', name: '前のタブへ', value: 'Command + Shift + [')
      expect(result[:changes]).to eq([{ address: { file: 'shortcuts.yaml', path: %w[shortcuts 前のタブへ] }, value: 'Command + Shift + [' }])
      expect { plan(op: 'create', kind: 'shortcut', name: '前のタブへ', value: 'KC_A', changes: to_changes(result[:changes])) }
        .to raise_error(plan_edits::InvalidChange) { |e| expect(e.field).to eq('edit.name') }
    end
  end
end
