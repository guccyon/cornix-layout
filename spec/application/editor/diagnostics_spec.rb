# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Cornix::Application::Editor::Diagnostics do
  let(:env) { Cornix::Application::Environment.new(config_dir: File.join(__dir__, '../../fixtures/test_config')) }
  let(:reading) { Cornix::Application::Editor::ProfileReading.read(env) }

  # 今の意味検証にはファイル全体を指す規則がないので、Profile#diagnostics の結果を差し替えて確かめる
  def located(*diagnostics)
    profile = double('profile', diagnostics: diagnostics)
    fake = double('reading', ok?: true, profile: profile, repository: reading.repository)
    allow(fake).to receive(:document) { |rel| reading.document(rel) }
    described_class.new(fake, env.capabilities).call
  end

  it '意味検証のファイル全体の問題は file だけ、一覧全体は "<ディレクトリ>/"、知らないパスはどちらも省く' do
    result = located(Cornix::Domain::Diagnostic.error('layers[1]', 'ファイル'), Cornix::Domain::Diagnostic.warning('layers', '一覧'),
                     Cornix::Domain::Diagnostic.error('somewhere', 'どこか'))
    expect(result).to eq([
                           { severity: 'error', message: 'ファイル', source: 'semantic', file: 'layers/1_layer_1.yaml' },
                           { severity: 'warning', message: '一覧', source: 'semantic', file: 'layers/' },
                           { severity: 'error', message: 'どこか', source: 'semantic' }
                         ])
  end

  it '意味検証の値の問題は Address と range' do
    result = located(Cornix::Domain::Diagnostic.error('layers[0].left_hand.row0.Q', 'Q'))
    expect(result.first).to include(address: { file: 'layers/0_layer_0.yaml', path: %w[mapping left_hand row0 Q] },
                                    range: { start: { line: 8, character: 9 }, end: { line: 8, character: 10 } })
  end
end
