# frozen_string_literal: true

require 'spec_helper'
require 'open3'
require 'rbconfig'
require 'json'
require_relative 'application/support/config_root'

# 設定 → compile → layout.vil、layout.vil → decompile → compile が、旧コードで作った .vil と 16bit 値で一致すること。
# 正解: spec/fixtures/layout.vil（test_config の compile 結果）、spec/fixtures/authors_baseline.vil
# （authors-keymap の config = spec/fixtures/authors_config を旧コードで compile した結果）
RSpec.describe 'end-to-end（cornix compile / decompile）' do
  include_context 'config root'

  repo = File.expand_path('..', __dir__)
  cases = { 'test_config' => 'layout.vil', 'authors_config' => 'authors_baseline.vil' }

  def cornix(*argv)
    out = StringIO.new
    status = Cornix::Interface::Cli::Main.new(env_factory: ->(_ws) { env }, out: out, err: out, input: StringIO.new).run(argv)
    [status, out.string]
  end

  cases.each do |config, vil|
    it "#{config} を compile すると #{vil} と同じ 16bit 値になる" do
      install_config(config)
      status, output = cornix('compile')
      expect(status).to eq(0), output
      expect(image(env.layout_path)).to eq(image(File.join(fixtures, vil)))
    end

    it "#{vil} を decompile して compile すると元に戻り、validate も通る" do
      source = install_file(vil, 'tmp/layout.vil')
      expect(cornix('decompile').first).to eq(0)
      expect(cornix('validate')).to eq([0, "✓ All validations passed\n"])
      expect(cornix('compile').first).to eq(0)
      expect(image(env.layout_path)).to eq(image(source))
    end
  end

  it 'bin/cornix をコピーした場所で compile / validate を実行できる（root は bin/ の親）' do
    %w[bin lib data].each { |dir| FileUtils.cp_r(File.join(repo, dir), File.join(@root, dir)) }
    install_config('authors_config')
    run = ->(*args) { Open3.capture2e(RbConfig.ruby, '-EUTF-8', File.join(@root, 'bin/cornix'), *args, chdir: @root) }
    output, status = run.('compile')
    expect(status.exitstatus).to eq(0), output
    expect(output).to include("✓ Compilation completed: #{File.join(File.realpath(@root), 'tmp/build/layout.vil')}")
    expect(image(env.layout_path)).to eq(image(File.join(fixtures, 'authors_baseline.vil')))
    output, status = run.('validate')
    expect([status.exitstatus, output]).to eq([0, "✓ All validations passed\n"])
    output, status = run.('nope')
    expect(status.exitstatus).to eq(1)
    expect(output).to include('知らないコマンドです: nope')
  end

  it 'bin/diff_layouts は 16bit 値で比べる（別表記は同じとみなす）' do
    diff = ->(a, b) { Open3.capture2e(RbConfig.ruby, '-EUTF-8', File.join(repo, 'bin/diff_layouts'), a, b) }
    install_config('authors_config')
    cornix('compile')
    output, status = diff.(File.join(fixtures, 'authors_baseline.vil'), env.layout_path)
    expect([status.exitstatus, output.lines.last]).to eq([0, "=== ✓ FILES ARE IDENTICAL ===\n"])
    output, status = diff.(File.join(fixtures, 'authors_baseline.vil'), File.join(fixtures, 'layout.vil'))
    expect(status.exitstatus).to eq(1)
    expect(output).to include('=== ✗ FILES DIFFER ===', 'Layout differences:', 'Setting keyboard.tapping_term (7): 180 vs 250')
  end
  it 'bin/rename_file は旧実装と同じオプションで名前を変え、結果を JSON で表示する' do
    install_config('authors_config')
    run = lambda do |*args|
      Open3.capture2e(RbConfig.ruby, '-EUTF-8', File.join(repo, 'bin/rename_file'), *args, chdir: @root)
    end
    args = ['--old-path', 'config/macros/07_clipboard_history.yml', '--new-basename', '07_clip.yml', '--name', 'Clip']
    output, status = run.(*args, '--dry-run')
    expect([status.exitstatus, JSON.parse(output)]).to match([0, include('success' => true, 'dry_run' => true,
                                                                         'validation_errors' => [])])
    output, status = run.(*args, '--cleanup-backup')
    expect(status.exitstatus).to eq(0), output
    expect(JSON.parse(output)).to include('success' => true, 'new_path' => end_with('/config/macros/07_clip.yml'),
                                          'backup_cleaned_up' => true)
    expect(read_config('layers/2_numbers.yml')).to include("V: Macro('Clip')")

    File.write(File.join(@root, 'plans.json'), JSON.generate([{ old_path: 'config/macros/07_clip.yml', new_basename: '08_x.yml' }]))
    output, status = run.('--batch', 'plans.json')
    expect(status.exitstatus).to eq(1)
    expect(JSON.parse(output)['errors']).to eq(["Plan 0: Index prefix mismatch: expected '07_', got '08_'"])
  end
end
