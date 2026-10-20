# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'

# profile/open の macros / tapDances / combos / shortcuts（protocol.md の 12.2）。Snapshot を通して確かめる
RSpec.describe Cornix::Application::Editor::Snapshot::Items do
  around do |example|
    Dir.mktmpdir('cornix-snapshot-items') do |dir|
      @root = File.realpath(dir)
      FileUtils.cp_r(File.join(__dir__, '../../../fixtures/test_config'), File.join(@root, 'profile'))
      example.run
    end
  end

  let(:workbench) { Cornix::Application::Editor::Workbench.new(root: @root) }
  let(:snapshot) { Cornix::Application::Editor::Snapshot.new(workbench).call(workbench.open('profile').id) }

  def write(rel, text)
    path = File.join(@root, 'profile', rel)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, text)
  end

  def address(file, *path) = { file: file, path: path }

  describe 'macros' do
    it '並びは references と同じで、手順のキーは Address と KeyValue（text はファイルの表記、canonical は名前参照なし）' do
      expect(snapshot[:macros].map { |m| m[:index] }).to eq(snapshot[:references][:macros].map { |m| m[:index] })
      macro = snapshot[:macros].first
      file = 'macros/00_macro.yaml'
      expect(macro).to include(index: 0, name: 'Macro 0', description: nil, file: file,
                               descriptionAddress: address(file, 'description'), icon: nil, preset: nil, presetAddress: nil,
                               summary: ['tap: [ ] Left'])
      step = macro[:steps].first
      expect(step).to include(address: address(file, 'sequence', 0), action: 'tap', keysAddress: address(file, 'sequence', 0, 'keys'))
      expect(step[:keys].first).to match(address: address(file, 'sequence', 0, 'keys', 0),
                                      value: { text: 'KC_LBRACKET', canonical: '[', code: 0x2F, kind: 'basic', display: { label: '[' } })
    end

    it '1 つの値で書いた keys は要素 1 つで Address は keys。delay / text は値の欄。手順のキーのマクロは M0 の形' do
      file = 'macros/09_mixed.yaml'
      write(file, <<~YAML)
        index: 9
        name: Mixed
        description: いろいろ
        sequence:
          - action: down
            keys: KC_LGUI
          - action: delay
            duration: 100
          - action: text
            content: hello
          - action: tap
            keys: [Macro(0)]
      YAML
      macro = snapshot[:macros].find { |m| m[:index] == 9 }
      expect(macro[:description]).to eq('いろいろ')
      expect(macro[:summary]).to eq(['down: ⌘', 'delay: 100ms', 'text: hello', 'tap: Macro 0'])
      down, delay, text, tap = macro[:steps]
      expect(down[:keys]).to match([{ address: address(file, 'sequence', 0, 'keys'), value: include(text: 'KC_LGUI') }])
      expect(delay).to eq(address: address(file, 'sequence', 1), action: 'delay',
                          duration: { address: address(file, 'sequence', 1, 'duration'), value: 100 })
      expect(text).to eq(address: address(file, 'sequence', 2), action: 'text',
                         content: { address: address(file, 'sequence', 2, 'content'), value: 'hello' })
      expect(tap[:keys].first[:value]).to include(text: 'Macro(0)', canonical: 'M0', kind: 'macro')
    end

    it 'preset: のマクロは steps が空で、preset と presetAddress、元のアプリのアイコン、summary は手順' do
      write('macros/12_frame.yaml', "index: 12\npreset: 'Figma:ツール:フレームツール'\n")
      macro = snapshot[:macros].find { |m| m[:index] == 12 }
      expect(macro).to include(preset: 'Figma:ツール:フレームツール', presetAddress: address('macros/12_frame.yaml', 'preset'),
                               icon: 'simple-icons:figma', steps: [])
      expect(macro[:summary]).not_to be_empty
    end
  end

  describe 'tapDances' do
    it '上の階層に書いた動作は ["on_tap"]、書いていない動作は value: null、tapping_term は書いた値' do
      td = snapshot[:tapDances].first
      file = 'tap_dance/00_tap_dance.yaml'
      expect(td).to include(index: 0, name: 'TapDance 0', file: file, descriptionAddress: address(file, 'description'),
                            tappingTerm: { address: address(file, 'tapping_term'), value: 200 })
      expect(td[:actions][:tap]).to match(address: address(file, 'on_tap'),
                                       value: include(text: 'OSL(4)', kind: 'layerAction'))
      expect(td[:actions].keys).to eq(%i[tap hold doubleTap tapHold])
    end

    it 'actions: の下に書いていれば ["actions", …]。注記は note、書いていない動作と tapping_term は null' do
      file = 'tap_dance/03_tab_escape.yaml'
      write(file, "index: 3\nname: Tab Escape\nactions:\n  on_tap: { key: Tab, note: タブ }\n")
      td = snapshot[:tapDances].find { |t| t[:index] == 3 }
      expect(td[:actions][:tap]).to match(address: address(file, 'actions', 'on_tap'),
                                       value: include(text: 'Tab', note: 'タブ'))
      expect(td[:actions][:hold]).to eq(address: address(file, 'actions', 'on_hold'), value: nil)
      expect(td[:tappingTerm]).to eq(address: address(file, 'tapping_term'), value: nil)
    end

    it '動作をどちらにも書いていなければ actions: の下' do
      file = 'tap_dance/03_empty.yaml'
      write(file, "index: 3\nname: Empty\n")
      td = snapshot[:tapDances].find { |t| t[:index] == 3 }
      expect(td[:actions].values.map { |slot| slot[:address][:path] }).to eq(
        [%w[actions on_tap], %w[actions on_hold], %w[actions on_double_tap], %w[actions on_tap_hold]]
      )
      expect(td[:actions].values.map { |slot| slot[:value] }.uniq).to eq([nil])
    end
  end

  describe 'combos' do
    it 'triggers は書いてある数だけ（KC_NO の詰め物も）、output は output_key' do
      combo = snapshot[:combos].first
      file = 'combos/00_combo.yaml'
      expect(combo).to include(index: 0, name: 'Combo 0', triggersAddress: address(file, 'trigger_keys'))
      expect(combo[:triggers].map { |slot| [slot[:address][:path], slot[:value][:text]] }).to eq(
        [[['trigger_keys', 0], 'KC_D'], [['trigger_keys', 1], 'KC_F'], [['trigger_keys', 2], 'KC_NO'], [['trigger_keys', 3], 'KC_NO']]
      )
      expect(combo[:output]).to match(address: address(file, 'output_key'),
                                   value: include(text: 'KC_LBRACKET', canonical: '['))
    end

    it 'output_key の注記は note' do
      write('combos/00_combo.yaml', "index: 0\nname: Combo 0\ntrigger_keys: [KC_D, KC_F]\noutput_key: { key: KC_ESC, note: 逃げる }\n")
      expect(snapshot[:combos].first[:output][:value]).to include(text: 'KC_ESC', note: '逃げる')
    end
  end

  describe 'shortcuts' do
    it 'ファイルの順に、["shortcuts", 名前] の Address とファイルの表記の KeyValue（名前の . もそのまま）' do
      write('shortcuts.yaml', "shortcuts:\n  前のタブへ: Command + Shift + [\n  a.b: Macro('Macro 0')\n")
      expect(snapshot[:shortcuts]).to match(
        [{ name: '前のタブへ', address: address('shortcuts.yaml', 'shortcuts', '前のタブへ'),
           value: include(text: 'Command + Shift + [', canonical: 'Shift + Command + [') },
         { name: 'a.b', address: address('shortcuts.yaml', 'shortcuts', 'a.b'),
           value: include(text: "Macro('Macro 0')", canonical: "Macro('Macro 0')", kind: 'macro') }]
      )
    end

    it 'shortcuts.yaml がなければ []' do
      expect(snapshot[:shortcuts]).to eq([])
    end
  end

  it '構造検証で読めなければ 4 つとも []' do
    write('layers/0_layer_0.yaml', "name: Broken\nindex: 0\nmapping: 1\n")
    expect(snapshot).to include(status: 'invalid', macros: [], tapDances: [], combos: [], shortcuts: [])
  end

  it 'レイヤーには descriptionAddress' do
    expect(snapshot[:layers][1][:descriptionAddress]).to eq(address('layers/1_layer_1.yaml', 'description'))
  end
end
