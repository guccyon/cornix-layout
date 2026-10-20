# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'

# profile/planEdits の書き換えを当てた設定を compile すると、同じ変更を手で直した設定と同じ 16bit 値になり、
# 変えていない行は変わらない（作者のプロファイル spec/fixtures/authors_config の写しで確かめる）
RSpec.describe 'profile/planEdits の書き換えと compile' do
  around do |example|
    Dir.mktmpdir('cornix-plan-compile') do |dir|
      @root = File.realpath(dir)
      example.run
    end
  end

  # 2 つの写しに共通の下ごしらえ（まだ書かれていない場所・値のない見出し・注記付きで引用符付きの値・0 / 1 で書いた真偽値を作る）
  def prepare(dir)
    FileUtils.cp_r(File.join(__dir__, '../../fixtures/authors_config'), dir)
    edit(dir, 'layers/0_base.yml') { |t| t.sub("      T: T\n", '') }
    edit(dir, 'layers/1_symbols.yml') { |t| t.sub('Q: Question', 'Q: { key: Question, note: 疑問符 }') }
    edit(dir, 'layers/1_symbols.yml') { |t| t.sub('W: DoubleQuote', "W: { key: '1', note: 数字 }") }
    # 左手の row2 を値のない見出しにする
    edit(dir, 'layers/6_empty.yml') { |t| t.sub(/^    row2:\n(?:      .*\n){6}(?=    row3:)/) { "    row2:\n" }.tap { |x| raise if x == t } }
    edit(dir, 'settings/qmk_settings.yaml') do |t|
      t.sub("  flow_tap: 120\n", '').sub("  oneshot_timeout: 1000\n", '').sub('permissive_hold: false', 'permissive_hold: 0')
    end
  end

  def edit(dir, rel)
    path = File.join(dir, rel)
    File.write(path, yield(File.read(path)))
  end

  # 手で直したもの
  def edit_by_hand(dir)
    edit(dir, 'layers/0_base.yml') do |t|
      t.sub("tab: TapDance('Tab Escape')", 'tab: Escape').sub("      R: R\n", "      R: R\n      T: Macro('Bracket Pair')\n")
       .sub("push: TapDance('Layer 3 Toggle')", 'push: Mute')
    end
    edit(dir, 'layers/1_symbols.yml') do |t|
      t.sub('{ key: Question, note: 疑問符 }', '{ key: Exclaim, note: 疑問符 }').sub("{ key: '1', note: 数字 }", "{ key: '2', note: 数字 }")
       .sub('R: NoKey', "R: Shortcut('VS Code:基本操作:コマンドパレット')")
    end
    edit(dir, 'layers/5_empty.yml') { |t| t.sub('lshift: NoKey', 'lshift: ","') }
    edit(dir, 'layers/3_function_keys.yml') do |t|
      t.sub("      tab: Escape\n      Q: F1\n      W: F2\n      E: F3\n", "      tab: Tab\n      Q: F5\n      W: F6\n      E: F7\n")
    end
    edit(dir, 'layers/4_ipad_base.yml') do |t|
      t.sub("      Q: Q\n      W: W\n      E: E\n", %(      Q: "1"\n      W: "#"\n      E: "!"\n))
    end
    edit(dir, 'layers/6_empty.yml') { |t| t.sub("    row2:\n", "    row2:\n      lshift: Enter\n      X: Space\n") }
    edit(dir, 'settings/qmk_settings.yaml') do |t|
      t.sub('tapping_term: 180', 'tapping_term: 200').sub('permissive_hold: 0', 'permissive_hold: 1')
       .sub("keyboard:\n", "keyboard:\n  oneshot_timeout: 900\n")
       .sub("  chordal_hold: true\n", "  chordal_hold: true\n  flow_tap: 100\n")
    end
  end

  def changes
    change = Cornix::Application::Editor::PlanEdits::Change
    key = ->(file, hand, group, symbol, value) { change.new(file: file, path: ['mapping', hand, group, symbol], value: value) }
    setting = ->(name, value) { change.new(file: 'settings/qmk_settings.yaml', path: ['keyboard', name], value: value) }
    [
      key.('layers/0_base.yml', 'left_hand', 'row0', 'tab', 'Escape'),
      key.('layers/0_base.yml', 'left_hand', 'row0', 'T', "Macro('Bracket Pair')"),
      change.new(file: 'layers/0_base.yml', path: %w[mapping encoders right push], value: 'Mute'),
      key.('layers/1_symbols.yml', 'left_hand', 'row0', 'Q', 'Exclaim'),
      key.('layers/1_symbols.yml', 'left_hand', 'row0', 'R', "Shortcut('VS Code:基本操作:コマンドパレット')"),
      key.('layers/1_symbols.yml', 'left_hand', 'row0', 'W', '2'),
      key.('layers/5_empty.yml', 'left_hand', 'row2', 'lshift', ','),
      # 隣り合う行（TextEdit.diff で複数行にまたがる 1 つの書き換えになる）
      *%w[tab Tab Q F5 W F6 E F7].each_slice(2).map { |sym, v| key.('layers/3_function_keys.yml', 'left_hand', 'row0', sym, v) },
      # 引用符が要る値
      *%w[Q 1 W # E !].each_slice(2).map { |sym, v| key.('layers/4_ipad_base.yml', 'left_hand', 'row0', sym, v) },
      # 値のない見出しの下に、position_map と逆の順で 2 つ足す
      key.('layers/6_empty.yml', 'left_hand', 'row2', 'X', 'Space'),
      key.('layers/6_empty.yml', 'left_hand', 'row2', 'lshift', 'Enter'),
      setting.('tapping_term', 200),
      setting.('permissive_hold', true),
      setting.('flow_tap', 100),
      setting.('oneshot_timeout', 900)
    ]
  end

  def apply_plan(dir, result)
    result[:files].each do |entry|
      path = File.join(dir, entry[:file])
      edits = entry[:edits].map do |e|
        s = e[:range][:start]
        t = e[:range][:end]
        range = Cornix::Storage::TextRange.new(start_line: s[:line], start_character: s[:character],
                                               end_line: t[:line], end_character: t[:character])
        Cornix::Storage::TextEdit.new(range: range, new_text: e[:newText])
      end
      File.write(path, Cornix::Storage::TextEdit.apply(File.read(path), edits))
    end
  end

  def compile(dir)
    env = Cornix::Application::Environment.new(root: @root, config_dir: dir)
    result = Cornix::Application::Compile.new(env).call(output: File.join(@root, "#{File.basename(dir)}.vil"))
    expect(result.path).not_to be_nil, result.report.inspect
    env.vil_file.read(result.path)
  end

  def files(dir) = Dir.glob('**/*', base: dir).select { |rel| File.file?(File.join(dir, rel)) }.sort.to_h { |rel| [rel, File.read(File.join(dir, rel))] }

  it '書き換えを当てた設定は、手で直した設定と同じ 16bit 値に compile され、中身も手で直したものと同じ' do
    planned = File.join(@root, 'planned')
    by_hand = File.join(@root, 'by_hand')
    prepare(planned)
    prepare(by_hand)
    edit_by_hand(by_hand)

    workbench = Cornix::Application::Editor::Workbench.new(root: @root)
    opened = workbench.open('planned')
    snapshot = Cornix::Application::Editor::Snapshot.new(workbench).call(opened.id)
    list = changes
    base = list.map(&:file).uniq.to_h { |file| [file, snapshot[:files].fetch(file)] }
    result = Cornix::Application::Editor::PlanEdits.new(workbench).call(opened.id, base_versions: base, changes: list)
    expect(result[:diagnostics]).to eq([])
    expect(result[:files].map { |f| f[:file] }).to eq(%w[layers/0_base.yml layers/1_symbols.yml layers/5_empty.yml layers/3_function_keys.yml
                                                         layers/4_ipad_base.yml layers/6_empty.yml settings/qmk_settings.yaml])
    apply_plan(planned, result)

    expect(files(planned)).to eq(files(by_hand))
    expect(compile(planned)).to eq(compile(by_hand))
    expect(compile(planned)).not_to eq(compile(File.join(@root, 'planned_before').tap { |d| prepare(d) }))
  end

  # 並びの位置は前の変更を当てたあとで数える。もとの引用符は保つ（content: "abc"）
  describe 'v0.2 の op（remove / insert / move と注記）' do
    def prepare_v02(dir)
      FileUtils.cp_r(File.join(__dir__, '../../fixtures/authors_config'), dir)
      File.write(File.join(dir, 'shortcuts.yaml'), "shortcuts:\n  前のタブへ: Command + Shift + [\n  次のタブへ: Command + Shift + ]\n")
    end

    # 手で直したもの
    def edit_v02_by_hand(dir)
      edit(dir, 'macros/00_bracket_pair.yml') do |t|
        t.sub(/^description: .*$/, 'description: テスト')
         .sub("sequence:\n- action: tap\n  keys:\n  - KC_LBRACKET\n  - KC_RBRACKET\n  - KC_LEFT\n",
              "sequence:\n- action: down\n  keys: [KC_LSHIFT]\n- action: tap\n  keys:\n  - KC_LBRACKET\n  - KC_RBRACKET\n" \
              "- action: up\n  keys: [KC_LSHIFT]\n")
      end
      edit(dir, 'macros/01_curly_brace_pair.yml') do |t|
        t.sub(/^sequence:\n(?:.*\n)*/, "sequence:\n- action: tap\n  keys:\n  - KC_LEFT\n  - KC_RIGHT\n- action: down\n  keys: KC_RSHIFT\n" \
                                       "- action: tap\n  keys:\n  - KC_LBRACKET\n  - KC_RBRACKET\n- action: up\n  keys: KC_LSHIFT\n")
      end
      edit(dir, 'macros/09_code_block.yml') do |t|
        t.sub('content: "``````"', 'content: "abc"').sub("  - KC_LEFT\n  - KC_LEFT\n  - KC_LEFT\n", "  - KC_LEFT\n")
         .sub("- action: tap\n", "- action: delay\n  duration: 50\n- action: tap\n")
      end
      edit(dir, 'tap_dance/04_tab_escape.yml') do |t|
        t.sub('on_tap: KC_TAB', 'on_tap: { key: KC_TAB, note: 注記 }').sub("  on_double_tap: KC_NO\n", '').sub("tapping_term: 200\n", '')
      end
      edit(dir, 'combos/00_bracket_pair.yml') do |t|
        t.sub("- KC_K\n- KC_L\n", "- KC_J\n- KC_K\n- KC_L\n").sub("output_key: Macro('Bracket Pair')", "output_key: { key: Macro('Bracket Pair'), note: メモ }")
      end
      edit(dir, 'layers/0_base.yml') do |t|
        t.sub("      tab: TapDance('Tab Escape')\n", '').sub("      cw: VolumeUp\n", '')
      end
      edit(dir, 'shortcuts.yaml') { |t| t.sub('Command + Shift + ]', 'Command + Option + Right') }
    end

    def v02_changes
      change = Cornix::Application::Editor::PlanEdits::Change
      m0 = 'macros/00_bracket_pair.yml'
      m1 = 'macros/01_curly_brace_pair.yml'
      m9 = 'macros/09_code_block.yml'
      td = 'tap_dance/04_tab_escape.yml'
      combo = 'combos/00_bracket_pair.yml'
      layer = 'layers/0_base.yml'
      [
        change.new(file: m0, path: ['sequence'], op: :insert, index: 0, value: { 'action' => 'down', 'keys' => ['KC_LSHIFT'] }),
        change.new(file: m0, path: ['sequence'], op: :insert, index: 2, value: { 'action' => 'up', 'keys' => ['KC_LSHIFT'] }),
        change.new(file: m0, path: ['sequence', 1, 'keys', 2], op: :remove),
        change.new(file: m0, path: ['description'], value: 'テスト'),
        change.new(file: m1, path: ['sequence'], op: :move, from: 3, to: 0),
        change.new(file: m1, path: ['sequence', 0, 'keys'], op: :insert, index: 1, value: 'KC_RIGHT'),
        change.new(file: m1, path: ['sequence', 1, 'keys'], value: 'KC_RSHIFT'),
        change.new(file: m9, path: ['sequence', 0, 'content'], value: 'abc'),
        change.new(file: m9, path: ['sequence', 1, 'keys', 1], op: :remove),
        change.new(file: m9, path: ['sequence', 1, 'keys', 1], op: :remove),
        change.new(file: m9, path: ['sequence'], op: :insert, index: 1, value: { 'action' => 'delay', 'duration' => 50 }),
        change.new(file: td, path: %w[actions on_tap], field: :note, value: '注記'),
        change.new(file: td, path: %w[actions on_double_tap], op: :remove),
        change.new(file: td, path: ['tapping_term'], op: :remove),
        change.new(file: combo, path: ['trigger_keys'], op: :insert, index: 2, value: 'KC_J'),
        change.new(file: combo, path: ['trigger_keys'], op: :move, from: 2, to: 0),
        change.new(file: combo, path: ['output_key'], field: :note, value: 'メモ'),
        change.new(file: layer, path: %w[mapping left_hand row0 tab], op: :remove),
        change.new(file: layer, path: %w[mapping encoders left cw], op: :remove),
        change.new(file: 'shortcuts.yaml', path: %w[shortcuts 次のタブへ], value: 'Command + Option + Right')
      ]
    end

    it '書き換えを当てた設定は、手で直した設定と同じ中身になり、同じ 16bit 値に compile される' do
      planned = File.join(@root, 'planned')
      by_hand = File.join(@root, 'by_hand')
      prepare_v02(planned)
      prepare_v02(by_hand)
      edit_v02_by_hand(by_hand)

      workbench = Cornix::Application::Editor::Workbench.new(root: @root)
      opened = workbench.open('planned')
      snapshot = Cornix::Application::Editor::Snapshot.new(workbench).call(opened.id)
      list = v02_changes
      base = list.map(&:file).uniq.to_h { |file| [file, snapshot[:files].fetch(file)] }
      result = Cornix::Application::Editor::PlanEdits.new(workbench).call(opened.id, base_versions: base, changes: list)
      expect(result[:diagnostics]).to eq([])
      apply_plan(planned, result)

      expect(files(planned)).to eq(files(by_hand))
      expect(compile(planned)).to eq(compile(by_hand))
    end
  end
end
