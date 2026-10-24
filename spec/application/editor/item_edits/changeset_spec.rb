# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'

RSpec.describe Cornix::Application::Editor::ItemEdits::Changeset do
  around do |example|
    Dir.mktmpdir('cornix-changeset') do |dir|
      @root = File.realpath(dir)
      FileUtils.cp_r(File.join(__dir__, '../../../fixtures/test_config'), File.join(@root, 'profile'))
      example.run
    end
  end

  let(:env) { Cornix::Application::Editor::Workbench.new(root: @root).open('profile').env }
  let(:reading) { Cornix::Application::Editor::ProfileReading.read(env) }
  let(:changeset) { described_class.new(reading) }

  it '変えたファイルだけを積んだ順に返す（作る・消す・改名。中身が戻ったファイルは入れない）' do
    original = reading.text('combos/00_combo.yaml')
    changeset.write('combos/00_combo.yaml', original.sub('Combo 0', 'Pair'))
    changeset.rename('combos/00_combo.yaml', 'combos/00_pair.yaml')
    changeset.write('combos/01_combo.yaml', "#{reading.text('combos/01_combo.yaml')}# x\n")
    changeset.write('combos/01_combo.yaml', reading.text('combos/01_combo.yaml'))
    changeset.create('combos/04_new.yaml', "index: 4\nname: New\ntrigger_keys: [KC_A]\noutput_key: KC_B\n")
    changeset.delete('combos/02_combo.yaml')
    files = changeset.to_protocol
    expect(files.map { |f| f.except(:edits, :baseVersion) }).to eq([
      { file: 'combos/00_combo.yaml', create: false, renameTo: 'combos/00_pair.yaml' },
      { file: 'combos/04_new.yaml', create: true },
      { file: 'combos/02_combo.yaml', create: false, delete: true }
    ])
    expect(files.map { |f| f[:baseVersion] }).to eq([reading.files['combos/00_combo.yaml'], nil, reading.files['combos/02_combo.yaml']])
    expect(changeset.touched).to eq(%w[combos/00_combo.yaml combos/04_new.yaml combos/02_combo.yaml])
    expect(changeset.created).to eq(['combos/04_new.yaml'])
    expect(changeset.exist?('combos/00_pair.yaml')).to be(true)
    expect(changeset.text('combos/02_combo.yaml')).to be_nil

    after = changeset.reading(env)
    expect(after.files.keys).to include('combos/00_pair.yaml', 'combos/04_new.yaml')
    expect(after.files.keys).not_to include('combos/00_combo.yaml', 'combos/02_combo.yaml')
    expect(after.profile.combos.map(&:name)).to eq(['Pair', 'Combo 1', 'Combo 3', 'New'])
    expect(File.exist?(File.join(@root, 'profile/combos/04_new.yaml'))).to be(false)
  end

  it '何も変えなければ空で、reading はもとのもの' do
    expect(changeset).to be_empty
    expect(changeset.reading(env)).to be(reading)
  end
end
