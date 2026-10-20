# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'

# 応答の形の約束は spec/fixtures/protocol/profile_plan_item_edit（適合テスト）。ここでは操作ごとの細かい振る舞いを確かめる
RSpec.describe Cornix::Application::Editor::ItemEdits do
  around do |example|
    Dir.mktmpdir('cornix-item-edits') do |dir|
      @root = File.realpath(dir)
      FileUtils.cp_r(File.join(__dir__, '../../fixtures', fixture), File.join(@root, 'profile'))
      example.run
    end
  end

  let(:fixture) { 'test_config' }
  let(:workbench) { Cornix::Application::Editor::Workbench.new(root: @root) }
  let(:opened) { workbench.open('profile') }
  let(:plan_edits) { Cornix::Application::Editor::PlanEdits }

  def path(rel) = File.join(@root, 'profile', rel)
  def read(rel) = File.read(path(rel))
  def write(rel, text) = FileUtils.mkdir_p(File.dirname(path(rel))).then { File.write(path(rel), text) }
  def version(rel) = Cornix::Storage::FileVersion.read(path(rel))

  # 今あるすべての設定ファイルの版（拡張が snapshot.files をそのまま送る形）
  def all_versions = Cornix::Application::Editor::ProfileReading.read(opened.env).files

  def edit(**fields) = described_class::Edit.new(**fields)

  def plan(base_versions: all_versions, **fields)
    described_class.new(workbench).call(opened.id, base_versions: base_versions, edit: edit(**fields))
  end

  # 書き換えを当てたテキスト（作るファイルは空から）
  def applied(result, file)
    entry = result[:files].find { |f| f[:file] == file } or raise "#{file} の書き換えがありません"
    edits = entry[:edits].map do |e|
      r = e[:range]
      range = Cornix::Storage::TextRange.new(start_line: r[:start][:line], start_character: r[:start][:character],
                                             end_line: r[:end][:line], end_character: r[:end][:character])
      Cornix::Storage::TextEdit.new(range: range, new_text: e[:newText])
    end
    Cornix::Storage::TextEdit.apply(entry[:create] ? '' : read(file), edits)
  end

  it 'ファイルは書かない' do
    before = Dir.glob(path('**/*')).sort.to_h { |f| [f, File.file?(f) ? File.read(f) : nil] }
    plan(op: 'create', kind: 'macro', name: 'New')
    plan(op: 'delete', kind: 'macro', name: 'Macro 0')
    plan(op: 'rename', kind: 'tapDance', name: 'TapDance 1', to: 'Screenshot')
    plan(op: 'renamePosition', hand: 'left', row: 0, col: 0, to: 'esc')
    expect(Dir.glob(path('**/*')).sort.to_h { |f| [f, File.file?(f) ? File.read(f) : nil] }).to eq(before)
  end

  describe 'create' do
    it '空いているいちばん小さい番号を使い、ファイル名はその番号と名前の slug（拡張子はディレクトリでいちばん多いもの）' do
      result = plan(op: 'create', kind: 'macro', name: 'Copy & Paste!')
      expect(result[:files].map { |f| f.slice(:file, :baseVersion, :create) })
        .to eq([{ file: 'macros/09_copy_paste.yaml', baseVersion: nil, create: true }])
      expect(YAML.safe_load(applied(result, 'macros/09_copy_paste.yaml')))
        .to eq('index' => 9, 'name' => 'Copy & Paste!', 'description' => '',
               'sequence' => [{ 'action' => 'tap', 'keys' => ['KC_NO'] }])
      expect(result[:diagnostics]).to eq([])
    end

    it '同じ番号と slug のファイルが（拡張子違いでも）あれば _2 を付ける' do
      write('macros/09_new.yml', "---\nindex: 30\nname: Other\nsequence:\n- action: tap\n  keys: KC_A\n")
      result = plan(op: 'create', kind: 'macro', name: 'New')
      expect(result[:files].map { |f| f[:file] }).to eq(['macros/09_new_2.yaml'])
    end

    it '空いている番号がなければ InvalidChange（field "edit"）' do
      (4..31).each { |i| write(format('combos/%02d_c.yaml', i), "index: #{i}\nname: C#{i}\ntrigger_keys: [KC_A]\noutput_key: KC_B\n") }
      expect { plan(op: 'create', kind: 'combo', name: 'Full') }
        .to raise_error(plan_edits::InvalidChange) { |e| expect(e.field).to eq('edit') }
    end

    it '名前の決まりに合わなければ InvalidChange（field "edit.name"）' do
      ['', '  ', ' a', "a\nb", 'Macro 0'].each do |name|
        expect { plan(op: 'create', kind: 'macro', name: name) }
          .to raise_error(plan_edits::InvalidChange) { |e| expect(e.field).to eq('edit.name') }
      end
    end

    it 'shortcuts.yaml がフロー表記なら足せないので NotLocal' do
      write('shortcuts.yaml', "shortcuts: { a: KC_A }\n")
      expect { plan(op: 'create', kind: 'shortcut', name: 'b', value: 'KC_B') }
        .to raise_error(plan_edits::NotLocal) { |e| expect(e.address).to eq({ file: 'shortcuts.yaml', path: %w[shortcuts b] }) }
    end

    it 'shortcuts: が空なら、その下に足す' do
      write('shortcuts.yaml', "shortcuts:\n")
      result = plan(op: 'create', kind: 'shortcut', name: 'b', value: 'Command + B')
      expect(applied(result, 'shortcuts.yaml')).to eq("shortcuts:\n  b: Command + B\n")
    end
  end

  describe 'delete' do
    it '番号で書いた参照も壊れる参照として返し、diagnostics は参照している側の意味検証のエラー' do
      result = plan(op: 'delete', kind: 'macro', name: 'Macro 0')
      expect(result[:files]).to eq([{ file: 'macros/00_macro.yaml', baseVersion: version('macros/00_macro.yaml'),
                                      create: false, edits: [], delete: true }])
      expect(result[:references]).to eq([{ file: 'layers/2_layer_2.yaml', path: %w[mapping left_hand row1 A] }])
      expect(result[:diagnostics]).to contain_exactly(
        include(severity: 'error', source: 'semantic', address: { file: 'layers/2_layer_2.yaml', path: %w[mapping left_hand row1 A] })
      )
    end

    it '消すファイルの中の自分への参照は入れない' do
      write('tap_dance/01_tap_dance.yaml', read('tap_dance/01_tap_dance.yaml').sub('on_tap_hold: KC_NO', 'on_tap_hold: TD(1)'))
      result = plan(op: 'delete', kind: 'tapDance', name: 'TapDance 1')
      expect(result[:references]).to eq([{ file: 'layers/3_layer_3.yaml', path: %w[mapping left_hand thumb_keys right] }])
    end

    it '同梱に同じ名前のあるショートカットは、消しても参照は壊れない' do
      name = 'Android Studio:一般:ビルド'
      write('shortcuts.yaml', "shortcuts:\n  #{name}: KC_A\n  other: KC_B\n")
      write('layers/0_layer_0.yaml', read('layers/0_layer_0.yaml').sub('tab: Tab', "tab: Shortcut('#{name}')"))
      result = plan(op: 'delete', kind: 'shortcut', name: name)
      expect(applied(result, 'shortcuts.yaml')).to eq("shortcuts:\n  other: KC_B\n")
      expect(result[:references]).to eq([])
      expect(result[:diagnostics]).to eq([])
    end

    it '最後の行（改行なし）のショートカットは前の行の改行ごと消す' do
      write('shortcuts.yaml', "shortcuts:\n  a: KC_A # メモ\n  b: KC_B")
      result = plan(op: 'delete', kind: 'shortcut', name: 'b')
      expect(applied(result, 'shortcuts.yaml')).to eq("shortcuts:\n  a: KC_A # メモ")
    end
  end

  describe 'rename' do
    it 'name の行・参照・ファイル名を変え、references は変える前の参照の場所' do
      write('layers/2_layer_2.yaml', read('layers/2_layer_2.yaml').sub('A: M0', "A: Macro('Macro 0') # 括弧"))
      result = plan(op: 'rename', kind: 'macro', name: 'Macro 0', to: 'Brackets')
      expect(result[:files].map { |f| f.slice(:file, :renameTo) })
        .to eq([{ file: 'macros/00_macro.yaml', renameTo: 'macros/00_brackets.yaml' }, { file: 'layers/2_layer_2.yaml' }])
      expect(applied(result, 'macros/00_macro.yaml')).to eq(read('macros/00_macro.yaml').sub('name: Macro 0', 'name: Brackets'))
      expect(applied(result, 'layers/2_layer_2.yaml')).to include("A: Macro('Brackets') # 括弧")
      expect(result[:references]).to eq([{ file: 'layers/2_layer_2.yaml', path: %w[mapping left_hand row1 A] }])
    end

    it 'name を省いたプリセットのマクロは name の行を足し、preset の名前の参照を置き換える' do
      preset = 'macOS:システム:ウィンドウキャプチャ'
      write('macros/20_capture.yaml', "index: 20\npreset: '#{preset}'\n")
      write('layers/0_layer_0.yaml', read('layers/0_layer_0.yaml').sub('tab: Tab', "tab: Macro('#{preset}')"))
      result = plan(op: 'rename', kind: 'macro', name: preset, to: 'Capture')
      expect(applied(result, 'macros/20_capture.yaml')).to eq("index: 20\nname: Capture\npreset: '#{preset}'\n")
      expect(applied(result, 'layers/0_layer_0.yaml')).to include("tab: Macro('Capture')")
      expect(result[:files].find { |f| f[:file] == 'macros/20_capture.yaml' }).not_to include(:renameTo)
    end

    it '新しいファイル名のファイルがほかにあれば、ファイル名は変えない' do
      write('combos/00_pair.yml', "index: 9\nname: Pair\ntrigger_keys: [KC_A]\noutput_key: KC_B\n")
      result = plan(op: 'rename', kind: 'combo', name: 'Combo 0', to: 'Pair 2')
      expect(result[:files].first).to include(file: 'combos/00_combo.yaml', renameTo: 'combos/00_pair_2.yaml')
      result = plan(op: 'rename', kind: 'combo', name: 'Combo 1', to: 'pair')
      expect(result[:files].first).to include(file: 'combos/01_combo.yaml')
      result = plan(op: 'rename', kind: 'combo', name: 'Combo 0', to: 'Pair!')
      expect(result[:files].first).not_to include(:renameTo)
    end

    it 'ショートカットの名前（キー）は、もとの引用符を保つ' do
      write('shortcuts.yaml', "shortcuts:\n  'a b': KC_A\n")
      write('layers/0_layer_0.yaml', read('layers/0_layer_0.yaml').sub('tab: Tab', "tab: Shortcut('a b')"))
      result = plan(op: 'rename', kind: 'shortcut', name: 'a b', to: "it's")
      expect(applied(result, 'shortcuts.yaml')).to eq("shortcuts:\n  \"it's\": KC_A\n")
      expect(applied(result, 'layers/0_layer_0.yaml')).to include(%(tab: Shortcut("it's")))
    end

    it '前後の compile の結果が違えば Unverified（-32061 の reason "verify"）' do
      mapper = opened.env.mapper
      allow(mapper).to receive(:to_image).and_wrap_original do |original, profile|
        image = original.call(profile)
        profile.tap_dances.any? { |t| t.name == 'Screenshot' } ? nil : image
      end
      expect { plan(op: 'rename', kind: 'tapDance', name: 'TapDance 1', to: 'Screenshot') }
        .to raise_error(described_class::Unverified) { |e|
          expect(e.reason).to eq('verify')
          expect(e.address).to eq({ file: 'tap_dance/01_tap_dance.yaml', path: ['name'] })
        }
    end

    it '知らない名前・ほかと同じ名前は InvalidChange' do
      expect { plan(op: 'rename', kind: 'layer', name: 'Nope', to: 'X') }
        .to raise_error(plan_edits::InvalidChange) { |e| expect(e.field).to eq('edit.name') }
      expect { plan(op: 'rename', kind: 'layer', name: 'Layer 1', to: 'Layer 2') }
        .to raise_error(plan_edits::InvalidChange) { |e| expect(e.field).to eq('edit.to') }
    end
  end

  describe 'renamePosition' do
    it 'position_map の要素と、書いてあるレイヤーのキーだけを書き換える（書いていないレイヤーはそのまま）' do
      write('layers/1_layer_1.yaml', read('layers/1_layer_1.yaml').sub(/^      tab: .*\n/, ''))
      write('layers/2_layer_2.yaml', read('layers/2_layer_2.yaml').sub(/^      tab: /, "      'tab': "))
      result = plan(op: 'renamePosition', hand: 'left', row: 0, col: 0, to: 'esc')
      files = result[:files].map { |f| f[:file] }
      expect(files).to include('position_map.yaml', 'layers/0_layer_0.yaml', 'layers/2_layer_2.yaml')
      expect(files).not_to include('layers/1_layer_1.yaml')
      expect(applied(result, 'position_map.yaml')).to include('row0: [esc, Q, W, E, R, T]')
      expect(applied(result, 'layers/0_layer_0.yaml')).to include("      esc: Tab\n")
      expect(applied(result, 'layers/2_layer_2.yaml')).to include("      'esc': ")
      expect(result[:references]).to eq([])
    end

    it '右手の row3 と親指のように、グループが違えば同じ名前でもよい' do
      result = plan(op: 'renamePosition', hand: 'right', row: 3, col: 3, to: 'down')
      expect(applied(result, 'position_map.yaml')).to include('thumb_keys: [down, middle, right]')
    end

    it '使えない名前・ない位置は InvalidChange' do
      expect { plan(op: 'renamePosition', hand: 'left', row: 0, col: 0, to: 'a b') }
        .to raise_error(plan_edits::InvalidChange) { |e| expect(e.field).to eq('edit.to') }
      expect { plan(op: 'renamePosition', hand: 'left', row: 0, col: 6, to: 'x') }
        .to raise_error(plan_edits::InvalidChange) { |e| expect(e.field).to eq('edit') }
    end
  end

  describe 'baseVersions' do
    it '書き換えないファイルの版は比べない' do
      versions = all_versions.merge('layers/5_layer_5.yaml' => 'sha256:0000')
      expect(plan(base_versions: versions, op: 'rename', kind: 'layer', name: 'Layer 1', to: 'Symbols')[:files].size).to eq(1)
    end

    it '名前が見つからないときは、先に送られたすべての版を比べる（古い画面のせいなら版の食い違い）' do
      versions = all_versions.merge('layers/5_layer_5.yaml' => 'sha256:0000')
      expect { plan(base_versions: versions, op: 'delete', kind: 'macro', name: 'Removed') }
        .to raise_error(plan_edits::VersionConflict) { |e| expect(e.files.keys).to eq(['layers/5_layer_5.yaml']) }
    end

    it '作るファイルは書かなくてよく、書くなら null' do
      expect(plan(base_versions: {}, op: 'create', kind: 'tapDance', name: 'T')[:files].size).to eq(1)
      expect { plan(base_versions: { 'tap_dance/03_t.yaml' => 'sha256:0000' }, op: 'create', kind: 'tapDance', name: 'T') }
        .to raise_error(plan_edits::VersionConflict)
    end
  end

  it '構造検証で読めないプロファイルでは InvalidChange（field "edit"）' do
    write('layers/0_layer_0.yaml', read('layers/0_layer_0.yaml').sub('tab: Tab', 'tab: NoSuchKey'))
    expect { plan(op: 'create', kind: 'macro', name: 'X') }
      .to raise_error(plan_edits::InvalidChange) { |e| expect(e.field).to eq('edit') }
  end
end
