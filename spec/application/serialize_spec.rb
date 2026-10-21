# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Cornix::Application::Serialize do
  let(:error) { Cornix::Domain::Diagnostic.error('layers/0_base.yaml: mapping.left_hand.row0.tab', '壊れている') }
  let(:warning) { Cornix::Domain::Diagnostic.warning('macros/', '多い') }

  it 'diagnostic(s) は { severity, path, message }' do
    expect(described_class.diagnostics([error, warning])).to eq(
      [{ 'severity' => 'error', 'path' => 'layers/0_base.yaml: mapping.left_hand.row0.tab', 'message' => '壊れている' },
       { 'severity' => 'warning', 'path' => 'macros/', 'message' => '多い' }]
    )
  end

  it 'changes は説明と Change#to_h を順に合わせる' do
    change = Cornix::Planning::Change::SetKeycode.new(layer: 1, row: 0, col: 2, from: 0, to: 4)
    expect(described_class.changes([change], ['レイヤー1 (0,2): KC_NO → KC_A'])).to eq(
      [{ 'description' => 'レイヤー1 (0,2): KC_NO → KC_A', 'kind' => 'set_keycode', 'layer' => 1, 'row' => 0, 'col' => 2,
         'from' => 0, 'to' => 4 }]
    )
  end

  it 'workspace は { config_dir, profile, source, root }、nil は nil' do
    workspace = Cornix::Application::Workspace.new(root: '/r', config_dir: '/r/profiles/a', profile_name: 'a',
                                                   source: :profile_option, settings_file: nil)
    expect(described_class.workspace(workspace)).to eq('config_dir' => '/r/profiles/a', 'profile' => 'a',
                                                       'source' => 'profile_option', 'root' => '/r')
    expect(described_class.workspace(nil)).to be_nil
  end

  it 'error は { error }' do
    expect(described_class.error('だめ')).to eq('error' => 'だめ')
  end

  describe Cornix::Application::ValidationReport do
    it 'to_h は { ok, diagnostics }。警告だけなら ok は真で、errors / warnings は表示用の文字列' do
      report = described_class.new(diagnostics: [warning])
      expect(report.to_h).to eq('ok' => true, 'diagnostics' => Cornix::Application::Serialize.diagnostics([warning]))
      expect(report.warnings).to eq(['macros/: 多い'])
      failed = described_class.new(diagnostics: [error, Cornix::Domain::Diagnostic.error('', 'path なし')])
      expect(failed.to_h['ok']).to be(false)
      expect(failed.errors).to eq(['layers/0_base.yaml: mapping.left_hand.row0.tab: 壊れている', 'path なし'])
    end
  end
end
