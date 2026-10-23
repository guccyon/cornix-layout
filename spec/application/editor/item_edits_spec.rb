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

    it 'ショートカットは未保存の変更に積む Change を返し（v0.5）、shortcuts: が空なら保存でその下に足す' do
      write('shortcuts.yaml', "shortcuts:\n")
      result = plan(op: 'create', kind: 'shortcut', name: 'b', value: 'Command + B')
      expect(result).to include(files: [], changes: [{ address: { file: 'shortcuts.yaml', path: %w[shortcuts b] }, value: 'Command + B' }])
      change = plan_edits::Change.new(file: 'shortcuts.yaml', path: %w[shortcuts b], value: 'Command + B')
      saved = plan_edits.new(workbench).call(opened.id, base_versions: all_versions.slice('shortcuts.yaml'), changes: [change])
      expect(applied(saved, 'shortcuts.yaml')).to eq("shortcuts:\n  b: Command + B\n")
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

  describe 'レイヤーの追加と削除（issue #84）' do
    def remove(rel) = FileUtils.rm(path(rel))

    it '選んだ番号で layers/<番号>_<名前>.yaml を作り、中身は LayerFile が受け付ける最小のもの' do
      remove('layers/5_layer_5.yaml')
      result = plan(op: 'create', kind: 'layer', name: 'Mouse Keys', index: 5)
      expect(result[:files].map { |f| f.slice(:file, :baseVersion, :create) })
        .to eq([{ file: 'layers/5_mouse_keys.yaml', baseVersion: nil, create: true }])
      expect(applied(result, 'layers/5_mouse_keys.yaml')).to eq(<<~YAML)
        ---
        name: Mouse Keys
        description: ''
        index: 5
        mapping:
          left_hand:
            row0: {}
            row1: {}
            row2: {}
            row3: {}
            thumb_keys: {}
          right_hand:
            row0: {}
            row1: {}
            row2: {}
            row3: {}
            thumb_keys: {}
      YAML
      expect(result[:diagnostics]).to eq([])
    end

    it '番号を省けば空いているいちばん小さい番号。既定の名前（Layer N）のファイル名は decompile と同じ layer' do
      remove('layers/7_layer_7.yaml')
      remove('layers/6_layer_6.yaml')
      result = plan(op: 'create', kind: 'layer', name: 'Layer 6')
      expect(result[:files].map { |f| f[:file] }).to eq(['layers/6_layer.yaml'])
    end

    it 'ある番号・範囲の外の番号は InvalidChange（field "edit.index"）、空いている番号がなければ field "edit"' do
      remove('layers/5_layer_5.yaml')
      expect { plan(op: 'create', kind: 'layer', name: 'X', index: 4) }
        .to raise_error(plan_edits::InvalidChange) { |e| expect(e.field).to eq('edit.index') }
      expect { plan(op: 'create', kind: 'layer', name: 'X', index: 10) }
        .to raise_error(plan_edits::InvalidChange) { |e| expect(e.field).to eq('edit.index') }
      write('layers/5_layer_5.yaml', "name: Five\nindex: 5\nmapping: { left_hand: {}, right_hand: {} }\n")
      expect { plan(op: 'create', kind: 'layer', name: 'X') }
        .to raise_error(plan_edits::InvalidChange) { |e| expect(e.field).to eq('edit') }
    end

    it '消すと references はそのレイヤーを指すレイヤー操作の欄（消すファイルの中は入れない）、diagnostics は参照している側の警告' do
      result = plan(op: 'delete', kind: 'layer', name: 'Layer 9')
      expect(result[:files]).to eq([{ file: 'layers/9_layer_9.yaml', baseVersion: version('layers/9_layer_9.yaml'),
                                      create: false, edits: [], delete: true }])
      expect(result[:references]).to eq([{ file: 'layers/0_layer_0.yaml', path: %w[mapping encoders right push] }])
      expect(result[:diagnostics]).to include(
        include(severity: 'warning', address: { file: 'layers/0_layer_0.yaml', path: %w[mapping encoders right push] })
      )
    end

    context 'レイヤーの名前が重なっているとき（空のレイヤーがどれも Empty など）' do
      before do
        %w[7 8].each { |n| write("layers/#{n}_layer_#{n}.yaml", read("layers/#{n}_layer_#{n}.yaml").sub("name: Layer #{n}", 'name: Empty')) }
      end

      it '消すのは file のレイヤー（同じ名前の最初のものではない）。ないファイルは field "edit.file"' do
        result = plan(op: 'delete', kind: 'layer', name: 'Empty', file: 'layers/8_layer_8.yaml')
        expect(result[:files].map { |f| f[:file] }).to eq(['layers/8_layer_8.yaml'])
        expect { plan(op: 'delete', kind: 'layer', name: 'Empty', file: 'layers/5_empty.yaml') }
          .to raise_error(plan_edits::InvalidChange) { |e| expect(e.field).to eq('edit.file') }
      end

      it '同じ名前のレイヤーを足せる（ファイル名は番号で分かれる）' do
        remove('layers/5_layer_5.yaml')
        result = plan(op: 'create', kind: 'layer', name: 'Empty', index: 5)
        expect(result[:files].map { |f| f[:file] }).to eq(['layers/5_empty.yaml'])
      end

      it '名前の変更も file のレイヤー。ほかのレイヤーと同じ名前にもできる' do
        result = plan(op: 'rename', kind: 'layer', name: 'Empty', file: 'layers/8_layer_8.yaml', to: 'Mouse')
        expect(result[:files].map { |f| f.slice(:file, :renameTo) }).to eq([{ file: 'layers/8_layer_8.yaml', renameTo: 'layers/8_mouse.yaml' }])
        result = plan(op: 'rename', kind: 'layer', name: 'Layer 6', file: 'layers/6_layer_6.yaml', to: 'Empty')
        expect(result[:files].map { |f| f[:file] }).to eq(['layers/6_layer_6.yaml'])
      end
    end
  end

  describe '未使用のファイル・番号の接頭辞のないファイル（issue #85）' do
    # 0_layer_0 と 1_layer_1 のあいだに並ぶ未使用のレイヤー（ずれると後ろのレイヤーがすべて別のファイルを指す）
    let(:spare_layer) { read('layers/1_layer_1.yaml').sub(/^index: 1\n/, '').sub('name: Layer 1', 'name: Spare') }

    before { write('layers/0_spare.yaml', spare_layer) }

    it '消す・名前を変えるのは、未使用のファイルを除いて対応させたそのレイヤーのファイル' do
      result = plan(op: 'delete', kind: 'layer', name: 'Layer 9')
      expect(result[:files].map { |f| f[:file] }).to eq(['layers/9_layer_9.yaml'])
      result = plan(op: 'rename', kind: 'layer', name: 'Layer 1', to: 'Symbols')
      expect(result[:files].map { |f| f.slice(:file, :renameTo) }).to eq([{ file: 'layers/1_layer_1.yaml', renameTo: 'layers/1_symbols.yaml' }])
      expect(applied(result, 'layers/1_layer_1.yaml')).to include('name: Symbols')
    end

    it '位置の名前の変更は、未使用のレイヤーのファイルのキーも書き換える' do
      result = plan(op: 'renamePosition', hand: 'left', row: 0, col: 0, to: 'esc')
      expect(result[:files].map { |f| f[:file] }).to include('layers/0_layer_0.yaml', 'layers/0_spare.yaml', 'layers/1_layer_1.yaml')
      expect(applied(result, 'layers/0_spare.yaml')).to include("      esc: ")
      expect(result[:diagnostics]).to eq([])
    end

    it '追加の空いている番号・名前の重複は使っているものだけで決める（未使用のファイルと同じファイル名なら _2）' do
      write('macros/09_spare.yaml', "name: Macro 0\nsequence: [{ action: tap, keys: [KC_A] }]\n")
      write('macros/09_new.yaml', "name: Old New\nsequence: [{ action: tap, keys: [KC_A] }]\n")
      result = plan(op: 'create', kind: 'macro', name: 'New')
      expect(result[:files].map { |f| f[:file] }).to eq(['macros/09_new_2.yaml'])
      expect(YAML.safe_load(applied(result, 'macros/09_new_2.yaml'))['index']).to eq(9)
      expect { plan(op: 'create', kind: 'macro', name: 'Old New') }.not_to raise_error
      expect { plan(op: 'rename', kind: 'macro', name: 'Macro 1', to: 'Old New') }.not_to raise_error
    end

    it '番号の接頭辞のないファイルも名前を変えられる（接頭辞は付けない）' do
      FileUtils.mv(path('macros/00_macro.yaml'), path('macros/brackets.yaml'))
      FileUtils.mv(path('combos/01_combo.yaml'), path('combos/07_pair.yaml'))
      result = plan(op: 'rename', kind: 'macro', name: 'Macro 0', to: 'Bracket Pair')
      expect(result[:files].first).to include(file: 'macros/brackets.yaml', renameTo: 'macros/bracket_pair.yaml')
      result = plan(op: 'rename', kind: 'combo', name: 'Combo 1', to: 'Jump')
      expect(result[:files].first).to include(file: 'combos/07_pair.yaml', renameTo: 'combos/07_jump.yaml')
    end

    it '未使用のファイルの構造の問題は diagnostics の warning（操作は止めない）' do
      write('tap_dance/spare.yaml', "name: Spare\nactions: { on_tap: Nope }\n")
      result = plan(op: 'rename', kind: 'tapDance', name: 'TapDance 1', to: 'Screenshot')
      expect(result[:diagnostics]).to contain_exactly(
        include(severity: 'warning', source: 'structure', address: { file: 'tap_dance/spare.yaml', path: %w[actions on_tap] })
      )
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

    it '知らない名前・ほかと同じ名前（レイヤーのほか）は InvalidChange' do
      expect { plan(op: 'rename', kind: 'layer', name: 'Nope', to: 'X') }
        .to raise_error(plan_edits::InvalidChange) { |e| expect(e.field).to eq('edit.name') }
      expect { plan(op: 'rename', kind: 'macro', name: 'Macro 0', to: 'Macro 1') }
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

  describe 'expandPreset' do
    let(:preset) { 'macOS:システム:ウィンドウキャプチャ' }

    it 'preset: の行を同梱の定義の手順の sequence: にし（表記は decompile の正規形）、ほかの行とコメントは保つ' do
      write('macros/20_capture.yaml', "# 画面\nindex: 20\nname: Capture\npreset: '#{preset}' # 同梱\ndescription: 撮る\n")
      result = plan(op: 'expandPreset', kind: 'macro', name: 'Capture')
      expect(result[:files].map { |f| f.slice(:file, :create) }).to eq([{ file: 'macros/20_capture.yaml', create: false }])
      expect(applied(result, 'macros/20_capture.yaml')).to eq(<<~YAML)
        # 画面
        index: 20
        name: Capture
        sequence:
        - action: down
          keys:
          - LGui
          - LShift
        - action: tap
          keys:
          - '4'
        - action: up
          keys:
          - LShift
          - LGui
        - action: tap
          keys:
          - Space
        description: 撮る
      YAML
      expect(result[:references]).to eq([])
      expect(result[:diagnostics]).to eq([])
    end

    it 'name を省いていれば name の行を足し（名前を変えない）、最後の行の preset: も置き換える' do
      name = 'Fusion 360:スケッチ:スプライン'
      write('macros/20_spline.yaml', "index: 20\npreset: '#{name}'")
      result = plan(op: 'expandPreset', kind: 'macro', name: name)
      expect(YAML.safe_load(applied(result, 'macros/20_spline.yaml')))
        .to eq('index' => 20, 'name' => name, 'sequence' => [{ 'action' => 'tap', 'keys' => %w[S P] }])
    end

    it '1 シーケンスの定義は、押して離す手順（修飾キーを押す → キー → 修飾キーを離す）にする' do
      write('macros/20_lock.yaml', "index: 20\nname: Lock\npreset: 'macOS:システム:画面ロック'\n")
      result = plan(op: 'expandPreset', kind: 'macro', name: 'Lock')
      expect(YAML.safe_load(applied(result, 'macros/20_lock.yaml'))['sequence'])
        .to eq([{ 'action' => 'down', 'keys' => %w[LCtrl LGui] }, { 'action' => 'tap', 'keys' => ['Q'] },
                { 'action' => 'up', 'keys' => %w[LGui LCtrl] }])
    end

    it 'preset: で書いていないマクロ・ないマクロは InvalidChange（field "edit.name"）' do
      expect { plan(op: 'expandPreset', kind: 'macro', name: 'Macro 0') }
        .to raise_error(plan_edits::InvalidChange) { |e| expect(e.field).to eq('edit.name') }
      expect { plan(op: 'expandPreset', kind: 'macro', name: 'Nope') }
        .to raise_error(plan_edits::InvalidChange) { |e| expect(e.field).to eq('edit.name') }
    end

    it 'フロー表記で書いたファイルは NotLocal' do
      write('macros/20_capture.yaml', "{ index: 20, name: Capture, preset: '#{preset}' }\n")
      expect { plan(op: 'expandPreset', kind: 'macro', name: 'Capture') }.to raise_error(plan_edits::NotLocal)
    end

    it '前後の compile の結果が違えば Unverified（address は preset: の場所）' do
      write('macros/20_capture.yaml', "index: 20\nname: Capture\npreset: '#{preset}'\n")
      mapper = opened.env.mapper
      allow(mapper).to receive(:to_image).and_wrap_original do |original, profile|
        image = original.call(profile)
        profile.macros.any? { |m| m.name == 'Capture' && m.preset.nil? } ? nil : image
      end
      expect { plan(op: 'expandPreset', kind: 'macro', name: 'Capture') }
        .to raise_error(described_class::Unverified) { |e|
          expect(e.reason).to eq('verify')
          expect(e.message).to include('preset を手順に展開すると')
          expect(e.address).to eq({ file: 'macros/20_capture.yaml', path: ['preset'] })
        }
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
    write('layers/0_layer_0.yaml', read('layers/0_layer_0.yaml').sub('tab: Tab', 'tab: [Tab]'))
    expect { plan(op: 'create', kind: 'macro', name: 'X') }
      .to raise_error(plan_edits::InvalidChange) { |e| expect(e.field).to eq('edit') }
  end

  it '読めない値（解析できないキーコード）があっても追加・削除はできるが、compile の結果を比べる名前の変更はしない（InvalidChange）' do
    write('layers/0_layer_0.yaml', read('layers/0_layer_0.yaml').sub('tab: Tab', 'tab: NoSuchKey'))
    expect(plan(op: 'create', kind: 'macro', name: 'X')[:files].size).to eq(1)
    expect { plan(op: 'rename', kind: 'macro', name: 'Macro 0', to: 'Y') }
      .to raise_error(plan_edits::InvalidChange) { |e| expect([e.field, e.message]).to eq(['edit', 'プロファイルに読めない値があるので、この操作はできません（先にその値を直してください。未保存の変更で直してもかまいません）']) }
  end
end
