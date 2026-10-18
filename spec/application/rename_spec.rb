# frozen_string_literal: true

require 'spec_helper'
require 'json'
require_relative 'support/config_root'

RSpec.describe Cornix::Application::RenameFiles do
  include_context 'config root'

  subject(:renamer) { described_class.new(env) }

  let(:plan) do
    { 'old_path' => 'config/macros/07_clipboard_history.yml', 'new_basename' => '07_clip_history.yml',
      'content_updates' => { 'name' => 'Clip History', 'description' => '履歴を開く' } }
  end

  before { install_config('authors_config') }

  it 'ファイル名と name / description を変え、名前参照を書き換え、compile の結果が変わらないことを確かめる' do
    numbers = read_config('layers/2_numbers.yml')
    outcome = renamer.call([plan])
    expect(outcome).to be_success
    expect(outcome.verified).to be(true)
    expect(outcome.completed.map(&:new_path)).to eq([config_file('macros/07_clip_history.yml')])
    expect(File).not_to exist(config_file('macros/07_clipboard_history.yml'))
    macro = read_config('macros/07_clip_history.yml')
    expect(macro).to include("name: Clip History\n", "description: 履歴を開く\n")
    # 参照はその部分だけ書き換わる（レイヤーの入れ子のマッピングもほかの行もそのまま）
    expect(read_config('layers/2_numbers.yml')).to eq(numbers.sub("Macro('Clipboard History')", "Macro('Clip History')"))
    expect(outcome.updated_references).to eq(['layers/2_numbers.yml'])
    expect(File.basename(outcome.backup_path)).to match(/\Aconfig\.backup_\d{8}_\d{6}\z/)
    expect(File).to exist(File.join(outcome.backup_path, '.backup_manifest.yaml'))
    expect(Cornix::Application::Validate.new(env).call).to be_valid
  end

  it '二重引用符の参照も書き換え、引用符の種類は保つ' do
    File.write(config_file('tap_dance/02_paste_variants.yml'),
               read_config('tap_dance/02_paste_variants.yml').sub("Macro('Copy Selected')", 'Macro("Copy Selected")'))
    outcome = renamer.call([{ old_path: 'macros/02_copy_selected.yml', new_basename: '02_copy_sel.yml',
                              content_updates: { name: 'Copy Sel' } }])
    expect(outcome).to be_success
    expect(read_config('tap_dance/02_paste_variants.yml')).to include('on_hold: Macro("Copy Sel")')
  end

  it 'タップダンスの名前も TapDance(...) の参照ごと変える' do
    outcome = renamer.call([{ 'old_path' => config_file('tap_dance/04_tab_escape.yml'),
                              'new_basename' => '04_tab_or_escape.yml', 'content_updates' => { 'name' => 'Tab/Escape' } }])
    expect(outcome).to be_success
    expect(read_config('layers/0_base.yml')).to include("tab: TapDance('Tab/Escape')")
  end

  it 'shortcuts.yaml の値の名前参照も書き換える' do
    File.write(config_file('shortcuts.yaml'), "shortcuts:\n  履歴: Macro('Clipboard History')\n")
    outcome = renamer.call([plan])
    expect(outcome).to be_success
    expect(outcome.verified).to be(true)
    expect(read_config('shortcuts.yaml')).to eq("shortcuts:\n  履歴: Macro('Clip History')\n")
    expect(outcome.updated_references).to include('shortcuts.yaml')
  end

  it 'name を省いたプリセットのマクロは preset の名前の参照を書き換える' do
    File.write(config_file('macros/20_capture.yml'), "index: 20\npreset: 'macOS:システム:ウィンドウキャプチャ'\n")
    File.write(config_file('layers/0_base.yml'),
               read_config('layers/0_base.yml').sub("tab: TapDance('Tab Escape')", "tab: Macro('macOS:システム:ウィンドウキャプチャ')"))
    outcome = renamer.call([{ old_path: 'macros/20_capture.yml', new_basename: '20_window_capture.yml',
                              content_updates: { name: 'Window Capture' } }])
    expect(outcome).to be_success
    expect(outcome.verified).to be(true)
    expect(read_config('layers/0_base.yml')).to include("tab: Macro('Window Capture')")
    expect(read_config('macros/20_window_capture.yml')).to include("name: Window Capture\n", 'preset: macOS:システム:ウィンドウキャプチャ')
  end

  it '事前検証: 番号の接頭辞の違い、行き先の重複、ないファイル。何も変えない' do
    plans = [
      plan.merge('new_basename' => '08_clip.yml'),
      plan.merge('old_path' => 'config/macros/00_bracket_pair.yml', 'new_basename' => '01_curly_brace_pair.yml'),
      plan.merge('old_path' => 'config/macros/99_none.yml')
    ]
    expect(plans.map { |p| renamer.check(p) }).to eq([
      ["Index prefix mismatch: expected '07_', got '08_'"],
      ["Index prefix mismatch: expected '00_', got '01_'",
       "Destination file already exists: #{config_file('macros/01_curly_brace_pair.yml')}"],
      ["File not found: #{config_file('macros/99_none.yml')}"]
    ])
    outcome = renamer.call(plans)
    expect(outcome).not_to be_success
    expect(outcome.errors.first).to start_with('Plan 0: Index prefix mismatch')
    expect(outcome.backup_path).to be_nil
    expect(File).to exist(config_file('macros/07_clipboard_history.yml'))
  end

  it '変更後に読み込めなければ（参照を書き換えられないなど）元に戻す' do
    # YAML の値として書けない名前（": " を含む）にすると、参照を書き換えた行が読めなくなる
    before = Dir.glob("#{env.config_dir}/**/*").sort.to_h { |f| [f, File.file?(f) && File.read(f)] }
    outcome = renamer.call([plan.merge('content_updates' => { 'name' => 'Clip: History' })])
    expect(outcome).not_to be_success
    expect(outcome.errors.first).to start_with('Compilation verification failed:')
    expect(outcome.rollback_completed).to be(true)
    after = Dir.glob("#{env.config_dir}/**/*").sort.to_h { |f| [f, File.file?(f) && File.read(f)] }
    expect(after).to eq(before)
  end

  it '変更前の設定が compile できなければ何もしない' do
    File.write(config_file('metadata.yaml'), "- 1\n")
    outcome = renamer.call([plan])
    expect(outcome.errors.first).to start_with('Configuration could not be compiled before rename:')
    expect(renamer.backups).to eq([])
  end

  it 'バックアップの一覧と削除' do
    renamer.call([plan])
    expect(renamer.backups.size).to eq(1)
    renamer.delete_backup(renamer.backups.first)
    expect(renamer.backups).to eq([])
  end
end

RSpec.describe Cornix::Application::SuggestRenames do
  include_context 'config root'

  subject(:suggest) { described_class.new(env) }

  let(:plans_json) do
    [{ 'old_path' => 'config/macros/00_macro.yaml', 'new_basename' => '00_hello.yaml',
       'content_updates' => { 'name' => 'Hello', 'description' => 'こんにちは' }, 'reasoning' => 'types hello' }]
  end

  before { install_config }

  it 'Claude に設定ファイルの中身を渡し、出力の ```json``` から計画を読む' do
    claude.output = "考えました\n```json\n#{JSON.generate(plans_json)}\n```\n"
    times = [10.0, 12.5]
    result = suggest.call(clock: -> { times.shift })
    expect(result).to be_ok
    expect(result.elapsed).to eq(2.5)
    expect(result.plans.map(&:to_h)).to eq([plans_json.first.slice('old_path', 'new_basename', 'content_updates')])
    expect(result.plans.first).to have_attributes(type: 'macro', reasoning: 'types hello', confidence: 'high')
    prompt = claude.prompts.first
    expect(prompt).to include('MACRO FILES:', 'File: config/macros/00_macro.yaml', 'LAYER FILES:', 'COMBO FILES:')
    expect(File.read(suggest.log_path)).to eq(claude.output)
    expect(suggest.cleanup).to contain_exactly('rename_plans.json', 'claude_output.log')
  end

  it 'claude がなければ :claude_missing、JSON がなければ :unparsed' do
    claude.available = false
    expect(suggest.call.status).to eq(:claude_missing)
    claude.available = true
    claude.output = 'ごめんなさい'
    expect(suggest.call.status).to eq(:unparsed)
  end

  it '手で書いた計画ファイルを読む（ない・壊れている）' do
    expect(suggest.load_plans.status).to eq(:missing)
    FileUtils.mkdir_p(env.tmp_dir)
    File.write(suggest.plans_path, '{oops')
    expect(suggest.load_plans.status).to eq(:invalid)
    File.write(suggest.plans_path, JSON.generate(plans_json))
    expect(suggest.load_plans.plans.size).to eq(1)
  end
end
