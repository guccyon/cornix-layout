# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'

RSpec.describe Cornix::Application::Editor::Diagnostics do
  let(:env) { Cornix::Application::Environment.new(config_dir: File.join(__dir__, '../../fixtures/test_config')) }
  let(:reading) { Cornix::Application::Editor::ProfileReading.read(env) }

  # 今の意味検証にはファイル全体を指す規則がないので、Profile#diagnostics の結果を差し替えて確かめる
  def located(*diagnostics)
    profile = double('profile', diagnostics: diagnostics)
    fake = double('reading', ok?: true, problems: [], profile: profile, repository: reading.repository)
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

  it '読めない値（解析できないキーコード）だけなら、構造の error のあとに意味検証の結果を続ける' do
    Dir.mktmpdir('cornix-diagnostics') do |dir|
      FileUtils.cp_r(File.join(__dir__, '../../fixtures/test_config/.'), dir)
      file = File.join(dir, 'layers/0_layer_0.yaml')
      File.write(file, File.read(file).sub('tab: Tab', 'tab: KC_FOOO').sub('Q: Q', 'Q: Macro(20)'))
      partial = Cornix::Application::Editor::ProfileReading.read(Cornix::Application::Environment.new(config_dir: dir))
      expect(partial).to be_ok
      expect(partial).not_to be_complete
      result = described_class.new(partial, env.capabilities).call
      expect(result.map { |d| [d[:source], d[:severity], d.dig(:address, :path)&.last] })
        .to eq([%w[structure error tab], %w[semantic error Q]])
    end
  end
end
