# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Cornix::Application::Editor::KeyValues do
  let(:env) { Cornix::Application::Environment.new(config_dir: File.join(__dir__, '../../fixtures/authors_config')) }
  let(:values) { described_class.new(env: env, profile: env.repository.load) }

  def value(text) = values.build(values.parse(text), text: text)

  it 'Shortcut(...) の見分けは parse と同じ読み方（かっこの内側の空白・二重引用符も）' do
    ["Shortcut('VS Code:基本操作:コマンドパレット')", "Shortcut( 'VS Code:基本操作:コマンドパレット' )",
     'Shortcut("VS Code:基本操作:コマンドパレット")'].each do |text|
      expect(value(text)).to include(origin: 'presetShortcut', icon: 'material-icon-theme:vscode', canonical: 'Shift + Command + P')
    end
    expect(value('Shift + Command + P')).not_to have_key(:origin)
  end

  it 'プロファイルが読めないときは、キーの表と同梱のショートカットだけで読む' do
    empty = described_class.new(env: env, profile: nil)
    expect(empty.layer_names).to eq({})
    expect(empty.build(empty.parse("Shortcut('Figma:ツール:移動ツール')"), text: "Shortcut('Figma:ツール:移動ツール')"))
      .to include(origin: 'presetShortcut', icon: 'simple-icons:figma')
    expect { empty.parse("Macro('Bracket Pair')") }.to raise_error(Cornix::UnknownKeycode)
  end
end
