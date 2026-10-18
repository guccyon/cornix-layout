# frozen_string_literal: true

require 'spec_helper'
require_relative 'support/storage_helpers'

RSpec.describe Cornix::Storage::ConfigRepository do
  include StorageHelpers

  let(:d) { Cornix::Domain }
  let(:k) { Cornix::Domain::Keycode }

  def basic(code) = k::Basic.new(code: code)

  describe '#load（spec/fixtures/test_config）' do
    let(:profile) { repository(StorageHelpers::TEST_CONFIG).load }

    it '問題なく読める' do
      expect(profile.layers.size).to eq(10)
      expect(profile.macros.map(&:index)).to eq([0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 11])
      expect(profile.tap_dances.size).to eq(3)
      expect(profile.combos.size).to eq(4)
      expect(profile.diagnostics.select(&:error?)).to be_empty
    end

    it 'レイヤーのキーを position_map の位置で持つ' do
      layer = profile.layer(0)
      tab = profile.position_map.position('left_hand', 'row0', 'tab')
      thumb = profile.position_map.position('left_hand', 'thumb_keys', 'middle')
      expect(layer.name).to eq('Layer 0')
      expect(layer.description).to be_nil
      expect(layer.key(tab)).to eq(basic(0x2B))
      expect(layer.key(thumb)).to eq(k::LayerTap.new(layer: d::LayerRef.new(index: 1), base: basic(0x2C)))
      expect(layer.encoder(:right).push).to eq(k::LayerAction.new(op: :one_shot, layer: d::LayerRef.new(index: 9)))
    end

    it '旧形式のタップダンス（on_tap などがトップレベル）を読む' do
      td = profile.tap_dance(0)
      expect(td.on_tap).to eq(k::LayerAction.new(op: :one_shot, layer: d::LayerRef.new(index: 4)))
      expect(td.on_double_tap).to eq(k::NO_KEY)
      expect(td.tapping_term).to eq(200)
    end

    it '旧 decompile の QSID の番号の形の設定を読む' do
      expect(profile.settings.values).to include(2 => 50, 7 => 250, 22 => 1)
    end

    it 'コンボのトリガーは書かれたまま（KC_NO を含む）' do
      expect(profile.combo(0).trigger_keys).to eq([basic(0x07), basic(0x09), k::NO_KEY, k::NO_KEY])
    end
  end

  describe '#load（形式の細部）' do
    it '.yml のファイルも読み、enabled は読み飛ばす' do
      with_config_copy do |dir|
        File.rename(File.join(dir, 'macros/00_macro.yaml'), File.join(dir, 'macros/00_macro.yml'))
        write_file(dir, 'macros/20_x.yml', "name: X\nenabled: true\nindex: 20\nsequence:\n- action: tap\n  keys: A\n")
        profile = repository(dir).load
        expect(profile.macro(0)).not_to be_nil
        expect(profile.macro(20).steps).to eq([d::MacroStep::Tap.new(keys: [basic(0x04)])])
      end
    end

    it '名前参照を Macro / TapDance の番号に解決する（ファイルの読む順に関係なく）' do
      with_config_copy do |dir|
        write_file(dir, 'tap_dance/09_ref.yaml',
                   "name: Ref\nindex: 9\nactions:\n  on_tap: Macro('Macro 3')\n  on_hold: TapDance('TapDance 1')\n")
        write_file(dir, 'combos/09_ref.yaml',
                   "name: Ref\nindex: 9\ntrigger_keys: [A, B]\noutput_key: TapDance('Ref')\n")
        profile = repository(dir).load
        expect(profile.tap_dance(9).on_tap).to eq(k::MacroCall.new(index: 3))
        expect(profile.tap_dance(9).on_hold).to eq(k::TapDanceCall.new(index: 1))
        expect(profile.combo(9).output_key).to eq(k::TapDanceCall.new(index: 9))
      end
    end

    it '省略した値を埋める（タップダンスの動作・tapping_term、エンコーダ、設定ファイル）' do
      with_config_copy do |dir|
        write_file(dir, 'tap_dance/09_min.yaml', "name: Min\nindex: 9\nactions:\n  on_tap: A\n")
        layer = YAML.load_file(File.join(dir, 'layers/0_layer_0.yaml'))
        layer['mapping'].delete('encoders')
        write_file(dir, 'layers/0_layer_0.yaml', layer.to_yaml)
        FileUtils.rm_r(File.join(dir, 'settings'))
        profile = repository(dir).load
        td = profile.tap_dance(9)
        expect([td.on_hold, td.on_double_tap, td.on_tap_hold]).to all(eq(k::NO_KEY))
        expect(td.tapping_term).to eq(250)
        expect(profile.layer(0).encoder(:left)).to eq(d::EncoderBinding.new(push: k::NO_KEY, ccw: k::NO_KEY, cw: k::NO_KEY))
        expect(profile.settings).to be_empty
      end
    end

    it '値のないキー（tab: ）は割り当てなし' do
      with_config_copy do |dir|
        path = File.join(dir, 'layers/0_layer_0.yaml')
        File.write(path, File.read(path).sub('tab: Tab', 'tab:'))
        profile = repository(dir).load
        expect(profile.layer(0).key(profile.position_map.position('left_hand', 'row0', 'tab'))).to be_nil
      end
    end

    it '設定は名前の形と番号の形のどちらも読み、真偽値は 0 / 1 にする' do
      with_config_copy do |dir|
        write_file(dir, 'settings/qmk_settings.yaml', "keyboard:\n  tapping_term: 180\n  chordal_hold: true\n" \
                                                      "vial:\n  combo_timing_window: 50\n99: 3\n")
        expect(repository(dir).load.settings.values).to eq(2 => 50, 7 => 180, 26 => 1, 99 => 3)
      end
    end
  end

  describe '#load の問題' do
    it 'すべてのファイルの問題を集めて InvalidConfig にする（ファイル: キーの位置: 内容）' do
      with_config_copy do |dir|
        write_file(dir, 'macros/00_macro.yaml', "index: 0\nname: 123\nsequence:\n- action: tap\n  keys: [NoSuchKey]\n")
        write_file(dir, 'tap_dance/00_tap_dance.yaml', "index: 0\nname: T\nactions:\n  on_tap: yes\n  on_hlod: A\n")
        problems = load_problems(dir)
        expect(problems).to include(
          match(/\Amacros\/00_macro.yaml: name: 名前（文字列）を書いてください: 整数 123 として読まれました。.*"123"/),
          match(/\Amacros\/00_macro.yaml: sequence\[0\]\.keys\[0\]: キーコード「NoSuchKey」を解釈できません/),
          match(/\Atap_dance\/00_tap_dance.yaml: actions\.on_tap: .*真偽値 true として読まれました（yes \/ no/),
          match(/\Atap_dance\/00_tap_dance.yaml: actions\.on_hlod: 未知のキーです（使えるキー: on_tap, on_hold/)
        )
        expect(problems.size).to eq(4)
      end
    end

    it 'InvalidConfig のメッセージは件数と問題の一覧' do
      with_config_copy do |dir|
        write_file(dir, 'combos/00_combo.yaml', "index: 0\nname: C\ntrigger_keys: []\noutput_key: A\n")
        expect { repository(dir).load }.to raise_error(Cornix::Storage::InvalidConfig) do |e|
          expect(e).to be_a(Cornix::ConfigError)
          expect(e.message).to eq("設定ファイルに 1 件の問題があります:\n  combos/00_combo.yaml: trigger_keys: trigger_keys が空です")
        end
      end
    end

    it 'YAML の文法エラー・キーの重複はファイル単位の問題' do
      with_config_copy do |dir|
        write_file(dir, 'layers/1_layer_1.yaml', "name: [\n")
        write_file(dir, 'macros/01_macro.yaml', "index: 1\nname: A\nname: B\nsequence: []\n")
        expect(load_problems(dir)).to contain_exactly(
          match(/\Alayers\/1_layer_1.yaml: YAML の文法エラーです/),
          'macros/01_macro.yaml: キー「name」が重複しています（3 行）'
        )
      end
    end

    it 'metadata.yaml と position_map.yaml がなければ問題' do
      with_config_copy do |dir|
        File.delete(File.join(dir, 'metadata.yaml'))
        File.delete(File.join(dir, 'position_map.yaml'))
        expect(load_problems(dir)).to contain_exactly('metadata.yaml: ファイルがありません',
                                                      'position_map.yaml: ファイルがありません')
      end
    end

    it 'position_map にないキーの名前は使えるキーを示す' do
      with_config_copy do |dir|
        path = File.join(dir, 'layers/0_layer_0.yaml')
        File.write(path, File.read(path).sub('tab: Tab', 'tabb: Tab'))
        expect(load_problems(dir)).to eq(['layers/0_layer_0.yaml: mapping.left_hand.row0.tabb: position_map の ' \
                                          'left_hand.row0 にないキーです（使えるキー: tab, Q, W, E, R, T）'])
      end
    end

    it 'レイヤーの必須の項目とファイル名の番号' do
      with_config_copy do |dir|
        path = File.join(dir, 'layers/2_layer_2.yaml')
        File.write(path, File.read(path).sub('index: 2', 'index: 3').sub(/^    row3:/, '    row9:'))
        expect(load_problems(dir)).to contain_exactly(
          match(/\Alayers\/2_layer_2.yaml: mapping.left_hand.row9: 未知のキーです/),
          'layers/2_layer_2.yaml: mapping.left_hand: row3 がありません'
        )
        File.write(path, File.read(path).sub('row9:', 'row3:'))
        expect(load_problems(dir)).to eq(['layers/2_layer_2.yaml: index: ファイル名の番号（2）と index（3）が違います'])
      end
    end

    it 'マクロの命令の問題' do
      with_config_copy do |dir|
        write_file(dir, 'macros/01_macro.yaml', <<~YAML)
          index: 1
          name: M
          sequence:
          - action: beep
          - action: delay
            duration: '100'
          - action: text
            content: 日本語
          - action: jump
          - action: tap
        YAML
        expect(load_problems(dir)).to eq([
          'macros/01_macro.yaml: sequence[0].action: beep は対応していません',
          'macros/01_macro.yaml: sequence[1].duration: 待ち時間（ミリ秒の整数）を書いてください: 文字列 "100" です（数値は引用符で囲まずに書いてください）',
          'macros/01_macro.yaml: sequence[2].content: text は ASCII のみです: "日本語"',
          'macros/01_macro.yaml: sequence[3].action: 未知の action です: jump（使える action: tap / down / up / delay / text）',
          'macros/01_macro.yaml: sequence[4]: keys がありません'
        ])
      end
    end

    it '設定の問題' do
      with_config_copy do |dir|
        write_file(dir, 'settings/qmk_settings.yaml', "keyboard:\n  taping_term: 1\n  chordal_hold: 2\n" \
                                                      "  tapping_term: '180'\nmouse: {}\n'7': 1\n")
        expect(load_problems(dir)).to contain_exactly(
          match(/\Asettings\/qmk_settings.yaml: keyboard.taping_term: 未知の設定です（使える設定: oneshot_timeout, tapping_term/),
          'settings/qmk_settings.yaml: keyboard.chordal_hold: 値は 0〜1 です: 2',
          match(/\Asettings\/qmk_settings.yaml: keyboard.tapping_term: 0 以上の整数を書いてください: 文字列 "180" です/),
          'settings/qmk_settings.yaml: mouse: 未知のキーです（使えるキー: keyboard, vial、または QSID の番号）'
        )
      end
    end

    it '番号・tapping_term の範囲' do
      with_config_copy do |dir|
        write_file(dir, 'tap_dance/09_x.yaml', "name: X\nindex: 300\ntapping_term: 70000\n")
        write_file(dir, 'combos/09_x.yaml', "name: X\nindex: '9'\ntrigger_keys: [A]\noutput_key: B\n")
        expect(load_problems(dir)).to contain_exactly(
          'tap_dance/09_x.yaml: index: タップダンス番号は 0〜255 です: 300',
          'tap_dance/09_x.yaml: tapping_term: tapping_term（ミリ秒）は 0〜65535 です: 70000',
          'combos/09_x.yaml: index: コンボ番号（0〜255 の整数）を書いてください: 文字列 "9" です（数値は引用符で囲まずに書いてください）'
        )
      end
    end

    it '同じ QSID を 2 回書くと問題' do
      with_config_copy do |dir|
        write_file(dir, 'settings/qmk_settings.yaml', "keyboard:\n  tapping_term: 180\n'7': 1\n")
        expect(load_problems(dir)).to eq(["settings/qmk_settings.yaml: 7: QSID 7 の設定が 2 回書かれています"])
      end
    end

    it 'metadata の型の問題' do
      with_config_copy do |dir|
        write_file(dir, 'metadata.yaml', "keyboard: yes\nversion: '1'\n")
        expect(load_problems(dir)).to contain_exactly(
          match(/\Ametadata.yaml: keyboard: キーボードの名前（文字列）を書いてください: 真偽値 true/),
          match(/\Ametadata.yaml: version: 0 以上の整数を書いてください: 文字列 "1" です/)
        )
      end
    end

    it 'position_map の問題は 1 件ずつ' do
      with_config_copy do |dir|
        path = File.join(dir, 'position_map.yaml')
        File.write(path, File.read(path).sub('[tab, Q, W, E, R, T]', '[tab, Q, W, E, R]').sub('[H, J', '[on, J'))
        expect(load_problems(dir)).to contain_exactly(
          'position_map.yaml: left_hand.row0 は 6 個です: 5 個',
          'position_map.yaml: right_hand.row1[0] のシンボルは [a-zA-Z0-9_-] の文字列です: true'
        )
      end
    end

    it '同じ名前で .yaml と .yml の両方があれば問題' do
      with_config_copy do |dir|
        FileUtils.cp(File.join(dir, 'metadata.yaml'), File.join(dir, 'metadata.yml'))
        expect(load_problems(dir)).to eq(['metadata.yml: metadata.yaml と同じ名前のファイルがあります。どちらか 1 つにしてください'])
      end
    end

    it '設定ディレクトリがなければ ConfigError' do
      expect { repository('/nonexistent/config').load }.to raise_error(Cornix::ConfigError, /設定ディレクトリがありません/)
    end
  end

  describe '#save' do
    let(:profile) { repository(StorageHelpers::TEST_CONFIG).load }

    it 'test_config を save して読み直すと同じ Profile になる' do
      Dir.mktmpdir do |dir|
        repo = repository(dir)
        repo.save(profile)
        expect(repo.load).to eq(profile)
      end
    end

    it '旧 YamlWriter と同じファイル名で書き、書いたファイルを返す' do
      Dir.mktmpdir do |dir|
        written = repository(dir).save(profile)
        expect(written).to include('metadata.yaml', 'position_map.yaml', 'settings/qmk_settings.yaml',
                                   'layers/0_layer.yaml', 'macros/00_macro.yaml', 'macros/10_macro.yaml',
                                   'tap_dance/00_tap_dance.yaml', 'combos/03_combo.yaml')
        expect(written.size).to eq(3 + 10 + 11 + 3 + 4)
        expect(written).to all(satisfy { |rel| File.file?(File.join(dir, rel)) })
      end
    end

    it '名前があればファイル名に使う（英数字以外は _、英数字が残らなければ種類の名前）' do
      with_config_copy do |dir|
        write_file(dir, 'macros/20_x.yaml', "name: 'Copy -- Line!'\nindex: 20\nsequence:\n- {action: tap, keys: A}\n")
        write_file(dir, 'macros/21_y.yaml', "name: 日本語\nindex: 21\nsequence:\n- {action: tap, keys: A}\n")
        Dir.mktmpdir do |out|
          written = repository(out).save(repository(dir).load)
          expect(written).to include('macros/20_copy_line.yaml', 'macros/21_macro.yaml')
        end
      end
    end

    it '参照は名前で、設定は名前の形で書く（旧 decompile の TD(4) / M2 / QSID の番号を直す）' do
      tab = profile.position_map.position('left_hand', 'row0', 'tab')
      layer = profile.layer(0).with(keys: profile.layer(0).keys.merge(tab => k::TapDanceCall.new(index: 2)))
      td = profile.tap_dance(1).with(on_hold: k::MacroCall.new(index: 4))
      changed = profile.with(layers: [layer] + profile.layers.drop(1),
                             tap_dances: profile.tap_dances.map { |t| t.index == 1 ? td : t })
      Dir.mktmpdir do |dir|
        repository(dir).save(changed)
        expect(File.read(File.join(dir, 'layers/0_layer.yaml'))).to include("tab: TapDance('TapDance 2')\n")
        expect(File.read(File.join(dir, 'tap_dance/01_tap_dance.yaml'))).to include("on_hold: Macro('Macro 4')\n")
        expect(YAML.load_file(File.join(dir, 'settings/qmk_settings.yaml'))).to eq(
          'keyboard' => { 'oneshot_timeout' => 1000, 'tapping_term' => 250, 'tap_code_delay' => 20,
                          'tap_hold_caps_delay' => 20, 'permissive_hold' => true, 'hold_on_other_key_press' => false,
                          'chordal_hold' => true, 'flow_tap' => 120 },
          'vial' => { 'combo_timing_window' => 50 }
        )
      end
    end

    it '各ファイルを旧 YamlWriter と同じ形で書く' do
      Dir.mktmpdir do |dir|
        repository(dir).save(profile)
        expect(File.read(File.join(dir, 'tap_dance/00_tap_dance.yaml'))).to eq(<<~YAML)
          ---
          index: 0
          name: TapDance 0
          description: ''
          actions:
            on_tap: OSL(4)
            on_hold: MO(1)
            on_double_tap: NoKey
            on_tap_hold: NoKey
          tapping_term: 200
        YAML
        expect(File.read(File.join(dir, 'macros/00_macro.yaml'))).to eq(<<~YAML)
          ---
          index: 0
          name: Macro 0
          description: ''
          sequence:
          - action: tap
            keys:
            - "["
            - "]"
            - Left
        YAML
        expect(File.read(File.join(dir, 'combos/00_combo.yaml'))).to start_with("---\nindex: 0\nname: Combo 0\n")
        expect(File.read(File.join(dir, 'position_map.yaml'))).to include("  row0: [tab, Q, W, E, R, T]\n")
        layer = YAML.load_file(File.join(dir, 'layers/0_layer.yaml'))
        expect(layer.keys).to eq(%w[name description index mapping])
        expect(layer['mapping'].keys).to eq(%w[left_hand right_hand encoders])
        expect(layer['mapping']['left_hand']['thumb_keys']).to eq('left' => 'LGUI_T(KC_LANG2)', 'middle' => 'LT1(Space)',
                                                                  'right' => 'LT2(Escape)')
      end
    end

    it 'Profile でなければ InvalidValue' do
      expect { repository('x').save({}) }.to raise_error(Cornix::InvalidValue)
    end
  end

  describe '名前付きショートカット（shortcuts.yaml）' do
    def tab(profile) = profile.position_map.position('left_hand', 'row0', 'tab')
    def q(profile) = profile.position_map.position('left_hand', 'row0', 'Q')

    def with_shortcuts(dir)
      write_file(dir, 'shortcuts.yaml', <<~YAML)
        shortcuts:
          前のタブへ: Command + Shift + [
          コピー: Macro('Macro 3')
      YAML
      path = File.join(dir, 'layers/0_layer_0.yaml')
      File.write(path, File.read(path).sub('tab: Tab', "tab: Shortcut('前のタブへ')").sub('Q: Q', "Q: Shortcut('コピー')"))
    end

    it "Shortcut('名前') を定義のキーコードにし、Profile#shortcuts に定義を持つ（compile の結果は直接書いたときと同じ）" do
      with_config_copy do |dir|
        with_shortcuts(dir)
        profile = repository(dir).load
        expect(profile.layer(0).key(tab(profile))).to eq(notation.parse('Shift + Command + ['))
        expect(profile.layer(0).key(q(profile))).to eq(k::MacroCall.new(index: 3))
        expect(profile.shortcuts.names).to eq(%w[前のタブへ コピー])
      end
    end

    it 'タップダンス・コンボ・エンコーダでも使える' do
      with_config_copy do |dir|
        with_shortcuts(dir)
        write_file(dir, 'tap_dance/09_ref.yaml', "name: Ref\nindex: 9\nactions:\n  on_tap: Shortcut('前のタブへ')\n")
        write_file(dir, 'combos/09_ref.yaml', "name: Ref\nindex: 9\ntrigger_keys: [A, B]\noutput_key: Shortcut('コピー')\n")
        profile = repository(dir).load
        expect(profile.tap_dance(9).on_tap).to eq(notation.parse('Shift + Command + ['))
        expect(profile.combo(9).output_key).to eq(k::MacroCall.new(index: 3))
      end
    end

    it 'shortcuts.yaml がなければ空。shortcuts: が空でも空' do
      expect(repository(StorageHelpers::TEST_CONFIG).load.shortcuts).to be_empty
      with_config_copy do |dir|
        write_file(dir, 'shortcuts.yaml', "shortcuts:\n")
        expect(repository(dir).load.shortcuts).to be_empty
      end
    end

    it '定義にない名前の参照・定義の値の Shortcut(...)・解釈できない値・形の誤りは問題になる' do
      with_config_copy do |dir|
        write_file(dir, 'shortcuts.yaml',
                   "shortcuts:\n  A: Shortcut('B')\n  B: NoSuchKey\n  1: Tab\n  C: LT1(Shortcut('Good'))\n  Good: Tab\n")
        path = File.join(dir, 'layers/0_layer_0.yaml')
        File.write(path, File.read(path).sub('tab: Tab', "tab: Shortcut('nope')").sub('Q: Q', "Q: Shortcut('Good')"))
        # 正しい定義（Good）への参照は、ほかの定義が不正でも問題にならない
        expect(load_problems(dir)).to contain_exactly(
          "shortcuts.yaml: shortcuts.A: shortcuts.yaml の値には Shortcut(...) は書けません: Shortcut('B')",
          "shortcuts.yaml: shortcuts.C: shortcuts.yaml の値には Shortcut(...) は書けません: LT1(Shortcut('Good'))",
          match(/\Ashortcuts.yaml: shortcuts.B: キーコード「NoSuchKey」を解釈できません/),
          match(/\Ashortcuts.yaml: shortcuts: .*ショートカットの名前/),
          match(%r{\Alayers/0_layer_0.yaml: mapping.left_hand.row0.tab: .*ショートカット「nope」は shortcuts.yaml にも同梱のショートカット（data/shortcuts/）にも定義されていません})
        )
      end
      with_config_copy do |dir|
        write_file(dir, 'shortcuts.yaml', "shortcut:\n  A: Tab\n")
        expect(load_problems(dir)).to contain_exactly('shortcuts.yaml: shortcut: 未知のキーです（使えるキー: shortcuts）',
                                                      'shortcuts.yaml: shortcuts がありません')
      end
    end

    it 'save は定義のちょうど 1 つと同じ値を Shortcut(\'名前\') で書き、shortcuts.yaml は既存の書き方を残す' do
      with_config_copy do |dir|
        with_shortcuts(dir)
        profile = repository(dir).load
        Dir.mktmpdir do |out|
          FileUtils.cp(File.join(dir, 'shortcuts.yaml'), out)
          repository(out).save(profile)
          expect(File.read(File.join(out, 'layers/0_layer.yaml')))
            .to include("tab: Shortcut('前のタブへ')\n", "Q: Shortcut('コピー')\n")
          expect(File.read(File.join(out, 'shortcuts.yaml'))).to eq(<<~YAML)
            ---
            shortcuts:
              前のタブへ: Command + Shift + [
              コピー: Macro('Macro 3')
          YAML
          expect(repository(out).load).to eq(profile)
        end
      end
    end

    it 'save は既存の shortcuts.yml に書き、整数で書いた値は正規形にする' do
      with_config_copy do |dir|
        with_shortcuts(dir)
        File.write(File.join(dir, 'shortcuts.yml'), File.read(File.join(dir, 'shortcuts.yaml')).sub('Command + Shift + [', '0x0A2F'))
        File.delete(File.join(dir, 'shortcuts.yaml'))
        profile = repository(dir).load
        Dir.mktmpdir do |out|
          FileUtils.cp(File.join(dir, 'shortcuts.yml'), out)
          written = repository(out).save(profile)
          expect(written).to include('shortcuts.yml')
          expect(written).not_to include('shortcuts.yaml')
          expect(File.read(File.join(out, 'shortcuts.yml'))).to include("前のタブへ: Shift + Command + [\n")
          expect(repository(out).load).to eq(profile)
        end
      end
    end

    it 'save は新しい定義の値を正規形で書き、ショートカットがなければ shortcuts.yaml を書かない' do
      profile = repository(StorageHelpers::TEST_CONFIG).load
      Dir.mktmpdir do |dir|
        expect(repository(dir).save(profile)).not_to include('shortcuts.yaml')
        shortcuts = Cornix::Domain::ShortcutLibrary.new(entries: { 'Prev' => notation.parse('Cmd + Shift + [') })
        written = repository(dir).save(profile.with(shortcuts: shortcuts))
        expect(written).to include('shortcuts.yaml')
        expect(File.read(File.join(dir, 'shortcuts.yaml'))).to eq("---\nshortcuts:\n  Prev: Shift + Command + [\n")
      end
    end
  end

  describe '同梱のショートカット（data/shortcuts/）' do
    def tab(profile) = profile.position_map.position('left_hand', 'row0', 'tab')
    def q(profile) = profile.position_map.position('left_hand', 'row0', 'Q')

    def use(dir, tab_text, q_text = 'Q')
      path = File.join(dir, 'layers/0_layer_0.yaml')
      File.write(path, File.read(path).sub('tab: Tab', "tab: #{tab_text}").sub('Q: Q', "Q: #{q_text}"))
    end

    it "Shortcut('アプリ:カテゴリ:ラベル') で同梱の定義を引ける（Profile#shortcuts には入らない）" do
      with_config_copy do |dir|
        use(dir, "Shortcut('Spotify:再生:次のクリップ')")
        profile = repository(dir).load
        expect(profile.layer(0).key(tab(profile))).to eq(notation.parse('Command + Right'))
        expect(profile.shortcuts).to be_empty
      end
    end

    it 'shortcuts.yaml に同じ名前があれば利用者の定義が勝つ' do
      with_config_copy do |dir|
        write_file(dir, 'shortcuts.yaml', "shortcuts:\n  'Spotify:再生:次のクリップ': Ctrl + Right\n")
        use(dir, "Shortcut('Spotify:再生:次のクリップ')", "Shortcut('Spotify:再生:前のクリップ')")
        profile = repository(dir).load
        expect(profile.layer(0).key(tab(profile))).to eq(notation.parse('Ctrl + Right'))
        expect(profile.layer(0).key(q(profile))).to eq(notation.parse('Command + Left'))
      end
    end

    it 'マクロの keys では使えない（同梱の名前でも「使えません」になる）' do
      with_config_copy do |dir|
        path = Dir[File.join(dir, 'macros', '*.yaml')].min
        data = YAML.safe_load_file(path)
        data['sequence'] = [{ 'action' => 'tap', 'keys' => ["Shortcut('Spotify:再生:次のクリップ')"] }]
        File.write(path, data.to_yaml)
        expect(load_problems(dir)).to include(match(/Shortcut\(...\) はここでは使えません/))
      end
    end

    it 'shortcuts.yaml の値からは参照できない（Shortcut(...) は書けない）' do
      with_config_copy do |dir|
        write_file(dir, 'shortcuts.yaml', "shortcuts:\n  次へ: Shortcut('Spotify:再生:次のクリップ')\n")
        expect(load_problems(dir)).to include(match(/shortcuts.yaml の値には Shortcut\(...\) は書けません/))
      end
    end

    it 'save は同梱の定義と同じ値を Shortcut(...) で書かない（利用者の定義だけを使う）' do
      with_config_copy do |dir|
        use(dir, "Shortcut('Spotify:再生:次のクリップ')")
        profile = repository(dir).load
        Dir.mktmpdir do |out|
          repository(out).save(profile)
          layer = File.read(File.join(out, 'layers/0_layer.yaml'))
          expect(layer).to include("tab: Command + Right\n")
          expect(layer).not_to include('Shortcut(')
          expect(repository(out).load).to eq(profile)
        end
      end
    end

    it 'shortcut_catalog を差し替えられる（既定は Mapping::ShortcutCatalog.default）' do
      with_config_copy do |dir|
        use(dir, "Shortcut('X:Y')")
        catalog = Cornix::Mapping::ShortcutCatalog.new('X:Y' => 'Tab')
        repo = Cornix::Storage::ConfigRepository.new(dir, notation: notation, settings_catalog: settings_catalog,
                                                          shortcut_catalog: catalog)
        profile = repo.load
        expect(profile.layer(0).key(tab(profile))).to eq(notation.parse('Tab'))
        expect(load_problems(dir)).to include(match(/ショートカット「X:Y」は shortcuts.yaml にも同梱のショートカット/))
      end
    end
  end
end
