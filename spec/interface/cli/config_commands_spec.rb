# frozen_string_literal: true

require 'spec_helper'
require 'stringio'
require 'json'
require_relative '../../application/support/config_root'

RSpec.describe 'cornix compile / decompile / validate / cleanup / rename' do
  include_context 'config root'

  let(:out) { StringIO.new }
  let(:err) { StringIO.new }
  let(:input) { StringIO.new }

  def cornix(*argv)
    Cornix::Interface::Cli::Main.new(env_factory: ->(_ws) { env }, out: out, err: err, input: input).run(argv)
  end

  describe 'compile' do
    it '検証してから layout.vil を書く' do
      install_config('authors_config')
      expect(cornix('compile')).to eq(0)
      expect(out.string).to eq(<<~TEXT)
        🔍 Validating configuration...
        ✓ All validations passed
        ✓ Validation passed

        🔨 Compiling...
        ✓ Compiled: #{env.layout_path}

        ✓ Compilation completed: #{env.layout_path}
      TEXT
      expect(image(env.layout_path)).to eq(image(File.join(fixtures, 'authors_baseline.vil')))
    end

    it '-o はカレントからの相対パスも受け付け、ない親ディレクトリは作り、絶対パスで表示する' do
      install_config('authors_config')
      Dir.chdir(@root) { expect(cornix('compile', '-o', 'out/new/my.vil')).to eq(0) }
      path = File.join(File.realpath(@root), 'out', 'new', 'my.vil')
      expect(out.string).to end_with("✓ Compilation completed: #{path}\n")
      expect(image(path)).to eq(image(File.join(fixtures, 'authors_baseline.vil')))
      expect(File).not_to exist(env.layout_path)
    end

    it '検証に失敗したら書かずに exit 1' do
      install_config
      File.write(config_file('metadata.yaml'), "- 1\n")
      expect(cornix('compile')).to eq(1)
      expect(out.string).to include("✗ Validation failed:\n  Error: metadata.yaml: ",
                                    "\n❌ Validation failed. Fix errors before compiling.\n")
      expect(File).not_to exist(env.layout_path)
    end

    it 'config/ がなければ decompile を案内して exit 1' do
      expect(cornix('compile')).to eq(1)
      expect(out.string).to end_with("Error: #{env.config_dir} not found\nRun 'cornix decompile' first to create config files\n")
    end

    it '余分な引数は使い方の誤り' do
      expect(cornix('compile', 'x')).to eq(1)
      expect(err.string).to include('compile への余分な引数: x')
    end
  end

  describe 'validate' do
    it '問題がなければ exit 0、警告も表示する' do
      install_config
      File.write(config_file('layers/0_layer_0.yaml'), read_config('layers/0_layer_0.yaml').sub(/tab: .*/, 'tab: MO(9)'))
      File.delete(config_file('layers/9_layer_9.yaml'))
      expect(cornix('validate')).to eq(0)
      expect(out.string).to start_with("✓ All validations passed\n")
      expect(out.string).to include('⚠  Warning: layers/0_layer_0.yaml: mapping.left_hand.row0.tab: レイヤー 9 が定義されていません')
    end

    it '問題があれば一覧を表示して exit 1' do
      install_config
      File.write(config_file('macros/00_macro.yaml'), "name: [\n")
      expect(cornix('validate')).to eq(1)
      expect(out.string).to start_with("✗ Validation failed:\n  Error: macros/00_macro.yaml: YAML の文法エラー")
    end

    it 'config/ がなければ exit 1' do
      expect(cornix('validate')).to eq(1)
      expect(out.string).to eq("Error: #{env.config_dir} not found\n")
    end
  end

  describe 'decompile' do
    it '既定では tmp/layout.vil を読む' do
      input_path = install_file('layout.vil', 'tmp/layout.vil')
      expect(cornix('decompile')).to eq(0)
      expect(out.string).to start_with("Decompiling: #{input_path}\nOutput to: #{env.config_dir}\n\n")
      expect(out.string).to include("✓ Decompilation completed: #{env.config_dir}\n",
                                    "✓ Lock file created: #{File.join(env.config_dir, '.decompile.lock')}\n")
      expect(cornix('compile')).to eq(0)
      expect(image(env.layout_path)).to eq(image(input_path))
    end

    it 'ファイルがなければ exit 1、config/ に設定があれば拒む' do
      expect(cornix('decompile', File.join(@root, 'none.vil'))).to eq(1)
      expect(out.string).to eq("Error: #{File.join(@root, 'none.vil')} not found\n")
      install_config
      expect(cornix('decompile', File.join(fixtures, 'layout.vil'))).to eq(1)
      expect(out.string).to include('⚠️  Error: config/ directory already contains configuration files.',
                                    'cornix decompile ~/Downloads/layout.vil')
    end
  end

  describe 'cleanup' do
    it '消すものがなければそう表示する' do
      expect(cornix('cleanup')).to eq(0)
      expect(out.string).to eq("✓ Nothing to clean up\n")
    end

    it 'ロックがなければ消す' do
      install_config
      expect(cornix('cleanup')).to eq(0)
      expect(out.string).to eq(<<~TEXT)
        ✓ Cleanup completed

        Deleted:
          - config/

        You can now run 'cornix decompile' to generate fresh config files
      TEXT
    end

    it 'ロックがあれば -f が必要で、y/N で確認する' do
      cornix('decompile', File.join(fixtures, 'layout.vil'))
      out.truncate(0) && out.rewind
      expect(cornix('cleanup')).to eq(1)
      expect(out.string).to start_with("⚠️  Protected: config/ directory has an active lock file\n\nLock file details:\n")
      expect(out.string).to include('  cornix cleanup -f')

      out.truncate(0) && out.rewind
      input.string = "n\n"
      expect(cornix('cleanup', '-f')).to eq(0)
      expect(out.string).to include('⚠️  WARNING: This will delete all config files and the lock file',
                                    'Are you sure you want to continue? [y/N]: ✓ Cleanup cancelled')
      expect(File).to exist(env.config_dir)

      input.string = "y\n"
      expect(cornix('cleanup', '--force')).to eq(0)
      expect(File).not_to exist(env.config_dir)
    end
  end

  describe 'rename' do
    let(:plans) do
      [
        { 'old_path' => 'config/macros/07_clipboard_history.yml', 'new_basename' => '07_clip_history.yml',
          'content_updates' => { 'name' => 'Clip History', 'description' => '履歴' }, 'reasoning' => 'opens history' },
        { 'old_path' => 'config/macros/00_bracket_pair.yml', 'new_basename' => '00_brackets.yml',
          'content_updates' => { 'name' => 'Brackets', 'description' => '[]' } }
      ]
    end

    before do
      install_config('authors_config')
      claude.output = "```json\n#{JSON.generate(plans)}\n```"
    end

    it 'Claude の提案を 1 件ずつ選び（e で編集）、名前を変えて検証する' do
      input.string = "e\n07_clipboard.yml\nClipboard\n\nn\nn\n"
      expect(cornix('rename')).to eq(0)
      text = out.string
      expect(text).to include('🤖 Step 2: Analyzing files with Claude AI...', '  ✓ Loaded 2 rename suggestion(s)',
                              '1. MACRO: 07_clipboard_history.yml', '  Reasoning:   opens history',
                              '  ✓ Added edited plan to queue', '  ⊘ Skipped', '  ✓ Renamed 1 file(s)',
                              '  ✓ Updated references in: layers/2_numbers.yml',
                              '  ✓ Layout structure preserved (compiled layout is identical)',
                              '  ✓ Removed: ', '📦 Backup directories found:', '  ℹ️  Backups preserved',
                              '✅ Rename completed successfully!')
      expect(File).to exist(config_file('macros/07_clipboard.yml'))
      expect(read_config('macros/07_clipboard.yml')).to include("name: Clipboard\n", "description: 履歴\n")
      expect(read_config('layers/2_numbers.yml')).to include("V: Macro('Clipboard')")
      expect(File).not_to exist(File.join(env.tmp_dir, 'rename_plans.json'))
    end

    it '何も選ばなければ何も変えない' do
      input.string = "n\nn\n"
      expect(cornix('rename')).to eq(0)
      expect(out.string).to include('✓ No files selected for rename')
      expect(Dir.glob("#{env.config_dir}.backup_*")).to eq([])
    end

    it 'claude がなければ案内して終わる' do
      claude.available = false
      expect(cornix('rename')).to eq(0)
      expect(out.string).to include("  ❌ Error: Claude CLI not found\n",
                                    '✓ All files already have meaningful names or Claude skill failed')
    end

    it 'JSON を取り出せなければ手で書いた計画ファイルを待つ' do
      claude.output = 'no json'
      FileUtils.mkdir_p(env.tmp_dir)
      input = Object.new
      plans_path = File.join(env.tmp_dir, 'rename_plans.json')
      answers = [-> { File.write(plans_path, JSON.generate(plans.first(1))) && "\n" }, -> { "y\n" }, -> { "y\n" }]
      input.define_singleton_method(:gets) { answers.shift&.call }
      status = Cornix::Interface::Cli::Main.new(env_factory: ->(_ws) { env }, out: out, err: err, input: input).run(['rename'])
      expect(status).to eq(0)
      expect(out.string).to include('  ⚠️  Could not extract JSON from Claude output',
                                    "  Please manually create rename plan at: #{plans_path}",
                                    '  ✓ Loaded 1 rename suggestion(s)', '  ✓ Deleted: config.backup_')
      expect(File).to exist(config_file('macros/07_clip_history.yml'))
    end

    it '失敗したら元に戻して exit 1' do
      claude.output = "```json\n#{JSON.generate([plans.first.merge('content_updates' => { 'name' => 'A: B' })])}\n```"
      input.string = "y\n"
      expect(cornix('rename')).to eq(1)
      expect(out.string).to include("❌ Rename failed:\n  Compilation verification failed: ",
                                    '✓ Changes rolled back successfully')
      expect(File).to exist(config_file('macros/07_clipboard_history.yml'))
    end

    it 'config/ がなければ exit 1、設定に問題があれば始めない' do
      FileUtils.rm_rf(env.config_dir)
      expect(cornix('rename')).to eq(1)
      expect(out.string).to include("❌ Error: config/ directory not found\n\nRun 'cornix decompile' first")
      install_config
      File.write(config_file('metadata.yaml'), "- 1\n")
      expect(cornix('rename')).to eq(1)
      expect(out.string).to include('❌ Fix the configuration before renaming.')
    end
  end
end
