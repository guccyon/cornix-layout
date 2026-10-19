# frozen_string_literal: true

require 'spec_helper'
require 'fileutils'
require 'tmpdir'

RSpec.describe Cornix::Application::Editor::ProfileReading do
  around do |example|
    Dir.mktmpdir('cornix-reading') do |dir|
      @dir = File.join(File.realpath(dir), 'profile')
      FileUtils.cp_r(File.join(__dir__, '../../fixtures/test_config'), @dir)
      example.run
    end
  end

  let(:env) { Cornix::Application::Environment.new(config_dir: @dir) }

  def path(rel) = File.join(@dir, rel)

  it '版は読んだバイト列のもので、読み込みも同じ中身を使う（読み込みの途中でディスクが変わっても食い違わない）' do
    original = Cornix::Storage::FileSource::Memory.method(:capture)
    allow(Cornix::Storage::FileSource::Memory).to receive(:capture) do |dir|
      original.call(dir).tap do
        File.write(path('layers/1_layer_1.yaml'), File.read(path('layers/1_layer_1.yaml')).sub('Layer 1', 'Changed'))
        FileUtils.cp(path('layers/9_layer_9.yaml'), path('layers/10_extra.yaml'))
      end
    end
    reading = described_class.read(env)
    expect(reading.profile.layers.map(&:name)).to include('Layer 1')
    expect(reading.profile.layers.size).to eq(10)
    expect(reading.files).not_to have_key('layers/10_extra.yaml')
    expect(reading.files['layers/1_layer_1.yaml']).not_to eq(Cornix::Storage::FileVersion.read(path('layers/1_layer_1.yaml')))
  end

  it 'settings/qmk_settings.yml のときは .yaml を null で入れず、settings_file は .yml' do
    File.rename(path('settings/qmk_settings.yaml'), path('settings/qmk_settings.yml'))
    reading = described_class.read(env)
    expect(reading.files).to include('settings/qmk_settings.yml' => a_string_starting_with('sha256:'))
    expect(reading.files).not_to have_key('settings/qmk_settings.yaml')
    expect(reading.settings_file).to eq('settings/qmk_settings.yml')
  end

  it '構造検証で読めなければ profile は nil で problems に問題' do
    File.write(path('layers/0_layer_0.yaml'), "name: Broken\nindex: 0\nmapping: 1\n")
    reading = described_class.read(env)
    expect(reading.ok?).to be(false)
    expect(reading.problems.map(&:file)).to include('layers/0_layer_0.yaml')
    expect(reading.document('layers/0_layer_0.yaml')).to be_a(Cornix::Storage::YamlDocument)
    expect(reading.document('shortcuts.yaml')).to be_nil
  end
end
