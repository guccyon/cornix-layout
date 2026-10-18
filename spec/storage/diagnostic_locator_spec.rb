# frozen_string_literal: true

require 'spec_helper'
require_relative 'support/storage_helpers'

RSpec.describe Cornix::Storage::DiagnosticLocator do
  include StorageHelpers

  subject(:locator) { described_class.new(StorageHelpers::TEST_CONFIG) }

  def at(path) = locator.locate_path(path)

  it 'レイヤーのキーとエンコーダは mapping の下' do
    expect(at('layers[0].left_hand.row0.tab')).to eq('layers/0_layer_0.yaml: mapping.left_hand.row0.tab')
    expect(at('layers[3].encoders.right.push')).to eq('layers/3_layer_3.yaml: mapping.encoders.right.push')
    expect(at('layers[1].index')).to eq('layers/1_layer_1.yaml: index')
    expect(at('layers[2]')).to eq('layers/2_layer_2.yaml')
  end

  it 'マクロの steps は sequence、keys が 1 つの文字列なら keys' do
    expect(at('macros[9].steps[1].keys[0]')).to eq('macros/10_macro.yaml: sequence[1].keys[0]')
    expect(at('macros[0].name')).to eq('macros/00_macro.yaml: name')
    with_config_copy do |dir|
      write_file(dir, 'macros/00_macro.yaml', "index: 0\nname: M\nsequence:\n- {action: tap, keys: A}\n")
      expect(described_class.new(dir).locate_path('macros[0].steps[0].keys[0]'))
        .to eq('macros/00_macro.yaml: sequence[0].keys')
    end
  end

  it 'preset: のマクロ（sequence がない）の手順は preset' do
    with_config_copy do |dir|
      write_file(dir, 'macros/00_macro.yaml', "index: 0\npreset: 'macOS:テキスト:コピー'\n")
      expect(described_class.new(dir).locate_path('macros[0].steps[1].keys[0]')).to eq('macros/00_macro.yaml: preset')
    end
  end

  it 'タップダンスの動作は actions: があれば actions の下' do
    expect(at('tap_dances[1].on_hold')).to eq('tap_dance/01_tap_dance.yaml: on_hold')

    with_config_copy(StorageHelpers::AUTHORS_CONFIG) do |dir|
      expect(described_class.new(dir).locate_path('tap_dances[1].on_hold'))
        .to eq('tap_dance/01_screen_capture_combo.yml: actions.on_hold')
    end
  end

  it 'コンボはそのまま' do
    expect(at('combos[0].trigger_keys[1]')).to eq('combos/00_combo.yaml: trigger_keys[1]')
    expect(at('combos[2].output_key')).to eq('combos/02_combo.yaml: output_key')
  end

  it '一覧全体のパスはディレクトリ、ファイルがない番号と知らないパスはそれとわかる形' do
    expect(at('macros')).to eq('macros/')
    expect(at('tap_dances')).to eq('tap_dance/')
    expect(at('combos[9].name')).to eq('combos/（10 番目のファイル）: name')
    expect(at('settings')).to eq('settings')
  end

  it 'Diagnostic を位置つきの Diagnostic にする' do
    diagnostic = Cornix::Domain::Diagnostic.warning('layers[0].left_hand.row0.tab', 'レイヤー 9 が定義されていません')
    located = repository(StorageHelpers::TEST_CONFIG).locate(diagnostic)
    expect(located).to eq(Cornix::Domain::Diagnostic.warning('layers/0_layer_0.yaml: mapping.left_hand.row0.tab',
                                                             'レイヤー 9 が定義されていません'))
  end

  it 'Profile#diagnostics の結果を位置にできる' do
    with_config_copy do |dir|
      path = File.join(dir, 'layers/0_layer_0.yaml')
      File.write(path, File.read(path).sub('tab: Tab', 'tab: M30'))
      repo = repository(dir)
      located = repo.load.diagnostics.map { |diag| repo.locate(diag).to_s }
      expect(located).to eq(['[error] layers/0_layer_0.yaml: mapping.left_hand.row0.tab: マクロ M30 が定義されていません'])
    end
  end
end
