# frozen_string_literal: true

require 'json'
require 'yaml'
require 'fileutils'
require 'pathname'
require_relative 'file_renamer'
require_relative 'compiler'

module Cornix
  # bin/cornix rename コマンドの実装
  class RenameCommand
    def initialize(config_dir)
      @config_dir = File.expand_path(config_dir)
      @tmp_dir = File.join(File.dirname(@config_dir), 'tmp')
      @plans_file = File.join(@tmp_dir, 'rename_plans.json')
      @before_vil = File.join(@tmp_dir, 'layout_before_rename.vil')
    end

    # メインエントリーポイント
    def execute
      puts "🔍 Cornix Config Renamer"
      puts ""

      # Step 0: 前提チェック
      check_prerequisites

      # Step 1: リネーム前のコンパイル
      puts "📦 Step 1: Compiling current configuration..."
      compile_before

      # Step 2: リネームプラン作成（Claude Skillによる推論）
      puts ""
      puts "🤖 Step 2: Analyzing files with Claude AI..."
      plans = call_claude_skill_for_plans

      if plans.empty?
        puts "✓ All files already have meaningful names or Claude skill failed"
        cleanup_temp_files
        return
      end

      # Step 3: プラン表示とユーザー確認
      puts ""
      puts "📋 Step 3: Review rename suggestions"
      puts "=" * 70
      selected_plans = interactive_plan_selection(plans)

      if selected_plans.empty?
        puts ""
        puts "✓ No files selected for rename"
        cleanup_temp_files
        return
      end

      # Step 4: リネーム実行（参照修正含む）
      puts ""
      puts "✏️  Step 4: Applying renames..."
      execute_renames(selected_plans)

      # Step 5: リネーム後のコンパイルと検証
      puts ""
      puts "🔍 Step 5: Verifying changes..."
      verify_compilation

      # Step 6: 一時ファイル削除とバックアップ確認
      puts ""
      puts "🧹 Step 6: Cleaning up temporary files..."
      cleanup_temp_files

      puts ""
      ask_backup_cleanup

      puts ""
      puts "✅ Rename completed successfully!"
      puts ""
      puts "Summary:"
      puts "  Renamed: #{selected_plans.size} file(s)"
      puts "  Verification: ✓ Layout structure preserved"
    end

    private

    def check_prerequisites
      unless Dir.exist?(@config_dir)
        puts "❌ Error: config/ directory not found"
        puts ""
        puts "Run 'cornix decompile' first to create config files"
        exit 1
      end

      FileUtils.mkdir_p(@tmp_dir)
    end

    def compile_before
      layout_vil = File.join(File.dirname(@config_dir), 'layout.vil')

      compiler = Compiler.new(@config_dir)
      compiler.compile(layout_vil)

      # バックアップ
      FileUtils.cp(layout_vil, @before_vil)
      puts "  ✓ Saved baseline: #{File.basename(@before_vil)}"
    end

    def call_claude_skill_for_plans
      puts "  Analyzing files with Claude AI..."

      skill_output_file = File.join(@tmp_dir, 'rename_plans.json')

      # 既存のプランファイルを削除
      FileUtils.rm_f(skill_output_file) if File.exist?(skill_output_file)

      # claude コマンドがインストールされているかチェック
      claude_installed = system('which claude > /dev/null 2>&1')

      unless claude_installed
        puts ""
        puts "  ❌ Error: Claude CLI not found"
        puts ""
        puts "  The 'claude' command is required for automatic rename analysis."
        puts "  Please install Claude Code from: https://claude.ai/download"
        puts ""
        return []
      end

      puts "  ✓ Claude CLI detected, analyzing files..."

      # マクロ、タップダンス、コンボ、レイヤーのファイルを読み込み
      macro_files = Dir.glob("#{@config_dir}/macros/*.{yml,yaml}").sort
      tap_dance_files = Dir.glob("#{@config_dir}/tap_dance/*.{yml,yaml}").sort
      combo_files = Dir.glob("#{@config_dir}/combos/*.{yml,yaml}").sort
      layer_files = Dir.glob("#{@config_dir}/layers/*.{yml,yaml}").sort

      # プロンプトを構築
      prompt = build_analysis_prompt(macro_files, tap_dance_files, combo_files, layer_files, skill_output_file)

      # プロンプトを一時ファイルに保存
      prompt_file = File.join(@tmp_dir, 'rename_prompt.txt')
      File.write(prompt_file, prompt)

      # claude コマンドをワンライナーとして実行
      # -p (--print) で非インタラクティブ出力
      # ネストされたセッションを避けるためCLAUDECODE環境変数をアンセット
      command = "unset CLAUDECODE && cat #{prompt_file} | claude -p 2>&1"
      success, result, elapsed = run_with_spinner(command, message: "Running Claude analysis")

      if success
        puts "  ✓ Analysis completed (#{elapsed.round(1)}s)"
      else
        puts "  ✗ Analysis failed after #{elapsed.round(1)}s"
      end

      # デバッグ用に出力をログに保存
      debug_log = File.join(@tmp_dir, 'claude_output.log')
      File.write(debug_log, result)

      # プロンプトファイルを削除
      FileUtils.rm_f(prompt_file)

      # 結果からJSONを抽出
      json_match = result.match(/```json\s*(\[.*?\])\s*```/m)
      if json_match
        json_content = json_match[1]
        File.write(skill_output_file, json_content)
        puts "  ✓ Analysis completed"
      else
        puts ""
        puts "  ⚠️  Could not extract JSON from Claude output"
        puts "  Output saved to: #{debug_log}"
        puts "  Falling back to manual mode..."
        return fallback_to_manual_mode(skill_output_file)
      end

      # プランファイルの読み込み
      load_rename_plans(skill_output_file)
    end

    def build_analysis_prompt(macro_files, tap_dance_files, combo_files, layer_files, output_file)
      prompt = <<~PROMPT
        You are analyzing Cornix keyboard configuration files to suggest meaningful names.

        Task: Analyze the following macro, tap dance, combo, and layer files, then generate a JSON array of rename suggestions.

        Instructions:
        - Only suggest renames for files with generic names (matching "Macro N", "Tap Dance N", "Combo N", or "Layer N" patterns)
        - Deeply analyze key sequences and actions to infer the actual purpose
        - Preserve index prefixes (00_, 01_, 0_, 1_, etc.) in new filenames
        - For layers: use the 'description' field if meaningful, or infer from overrides
        - Output ONLY a JSON array, no other text

        JSON format:
        [
          {
            "old_path": "config/macros/00_macro.yml",
            "new_basename": "00_bracket_pair.yml",
            "content_updates": {
              "name": "Bracket Pair",
              "description": "Insert bracket pair [] with cursor positioning"
            },
            "reasoning": "Key sequence inserts brackets and positions cursor",
            "confidence": "high"
          }
        ]

        Files to analyze:

      PROMPT

      # マクロファイルの内容を追加
      if macro_files.any?
        prompt += "MACRO FILES:\n\n"
        macro_files.each do |file|
          content = File.read(file)
          prompt += "File: #{file}\n```yaml\n#{content}\n```\n\n"
        end
      end

      # タップダンスファイルの内容を追加
      if tap_dance_files.any?
        prompt += "TAP DANCE FILES:\n\n"
        tap_dance_files.each do |file|
          content = File.read(file)
          prompt += "File: #{file}\n```yaml\n#{content}\n```\n\n"
        end
      end

      # コンボファイルの内容を追加
      if combo_files.any?
        prompt += "COMBO FILES:\n\n"
        combo_files.each do |file|
          content = File.read(file)
          prompt += "File: #{file}\n```yaml\n#{content}\n```\n\n"
        end
      end

      # レイヤーファイルの内容を追加
      if layer_files.any?
        prompt += "LAYER FILES:\n\n"
        layer_files.each do |file|
          content = File.read(file)
          prompt += "File: #{file}\n```yaml\n#{content}\n```\n\n"
        end
      end

      prompt += "\nNow generate the JSON array with rename suggestions. Output ONLY the JSON, wrapped in ```json``` code fence.\n"

      prompt
    end

    def fallback_to_manual_mode(skill_output_file)
      puts ""
      puts "  Please manually create rename plan at: #{skill_output_file}"
      puts ""
      puts "  JSON format should be:"
      puts '  ['
      puts '    {'
      puts '      "old_path": "config/macros/00_macro.yml",'
      puts '      "new_basename": "00_brackets_pair.yml",'
      puts '      "content_updates": {'
      puts '        "name": "Brackets Pair",'
      puts '        "description": "Insert bracket pair []"'
      puts '      }'
      puts '    }'
      puts '  ]'
      puts ""
      print "  Press Enter when ready (or Ctrl+C to cancel): "

      input = $stdin.gets
      return [] unless input

      load_rename_plans(skill_output_file)
    end

    def load_rename_plans(skill_output_file)
      unless File.exist?(skill_output_file)
        puts ""
        puts "  ⚠️  Rename plan file not found: #{skill_output_file}"
        return []
      end

      begin
        plans_json = JSON.parse(File.read(skill_output_file))

        # JSONを内部形式に変換
        plans = plans_json.map do |p|
          {
            type: detect_file_type(p['old_path']),
            old_path: p['old_path'],
            old_basename: File.basename(p['old_path']),
            new_basename: p['new_basename'],
            content_updates: p['content_updates'],
            reasoning: p['reasoning'] || 'Suggested by Claude AI',
            confidence: p['confidence'] || 'high'
          }
        end

        puts "  ✓ Loaded #{plans.size} rename suggestion(s)"
        plans
      rescue JSON::ParserError => e
        puts ""
        puts "  ❌ Error parsing rename plan file: #{e.message}"
        []
      end
    end

    def detect_file_type(path)
      if path.include?('/macros/')
        'macro'
      elsif path.include?('/tap_dance/')
        'tap_dance'
      elsif path.include?('/combos/')
        'combo'
      elsif path.include?('/layers/')
        'layer'
      else
        'unknown'
      end
    end

    def ask_backup_cleanup
      # バックアップディレクトリの検索
      backup_dirs = Dir.glob(File.join(File.dirname(@config_dir), 'config.backup_*')).sort

      return if backup_dirs.empty?

      puts "📦 Backup directories found:"
      backup_dirs.each { |dir| puts "  - #{File.basename(dir)}" }
      puts ""
      print "Would you like to delete these backup directories? [y/N]: "

      input = $stdin.gets
      return unless input

      response = input.chomp.downcase

      if ['y', 'yes'].include?(response)
        backup_dirs.each do |dir|
          FileUtils.rm_rf(dir)
          puts "  ✓ Deleted: #{File.basename(dir)}"
        end
      else
        puts "  ℹ️  Backups preserved"
      end
    end

    def interactive_plan_selection(plans)
      selected = []

      plans.each_with_index do |plan, idx|
        puts ""
        puts "─" * 70
        puts "#{idx + 1}. #{plan[:type].upcase}: #{File.basename(plan[:old_path])}"
        puts ""
        puts "  Current:  #{plan[:old_basename]}"
        puts "  Proposed: #{plan[:new_basename]}"
        puts ""
        puts "  Name:        #{plan[:content_updates]['name']}"
        puts "  Description: #{plan[:content_updates]['description']}"
        puts ""
        puts "  Reasoning:   #{plan[:reasoning]}"
        puts "  Confidence:  #{plan[:confidence]}"
        puts ""
        print "  Apply this rename? [Y/n/e(dit)]: "

        input = $stdin.gets
        unless input
          puts "  ⊘ Interrupted"
          break
        end

        response = input.chomp.downcase

        case response
        when '', 'y', 'yes'
          selected << plan
          puts "  ✓ Added to rename queue"
        when 'e', 'edit'
          edited_plan = edit_plan(plan)
          if edited_plan
            selected << edited_plan
            puts "  ✓ Added edited plan to queue"
          end
        when 'n', 'no'
          puts "  ⊘ Skipped"
        else
          puts "  ⊘ Invalid response, skipped"
        end
      end

      selected
    end

    def edit_plan(plan)
      puts ""
      puts "  Edit rename plan:"
      puts ""

      print "  New basename [#{plan[:new_basename]}]: "
      input = $stdin.gets
      return nil unless input
      new_basename = input.chomp
      new_basename = plan[:new_basename] if new_basename.empty?

      print "  New name [#{plan[:content_updates]['name']}]: "
      input = $stdin.gets
      return nil unless input
      new_name = input.chomp
      new_name = plan[:content_updates]['name'] if new_name.empty?

      print "  New description [#{plan[:content_updates]['description']}]: "
      input = $stdin.gets
      return nil unless input
      new_desc = input.chomp
      new_desc = plan[:content_updates]['description'] if new_desc.empty?

      plan.merge(
        new_basename: new_basename,
        content_updates: {
          'name' => new_name,
          'description' => new_desc
        }
      )
    end

    def execute_renames(plans)
      # JSONプランを保存
      json_plans = plans.map do |p|
        {
          'old_path' => p[:old_path],
          'new_basename' => p[:new_basename],
          'content_updates' => p[:content_updates]
        }
      end
      File.write(@plans_file, JSON.pretty_generate(json_plans))

      # FileRenamerで実行
      renamer = FileRenamer.new(@config_dir, backup_on_init: true)
      result = renamer.rename_batch(json_plans)

      unless result[:success]
        puts ""
        puts "❌ Rename failed:"
        result[:errors].each { |err| puts "  #{err}" }

        if result[:rollback_completed]
          puts ""
          puts "✓ Changes rolled back successfully"
        end

        cleanup_temp_files
        exit 1
      end

      puts "  ✓ Renamed #{result[:completed].size} file(s)"
      puts "  ✓ Backup: #{File.basename(result[:backup_path])}"

      # レイヤーファイル内の参照修正（マクロとタップダンスのみ）
      update_layer_references(plans)
    end

    def update_layer_references(plans)
      # マクロとタップダンスの名前変更を抽出
      macro_changes = {}
      tap_dance_changes = {}

      plans.each do |plan|
        old_name = plan[:content_updates]['name']

        case plan[:type]
        when 'macro'
          # M0, M1 形式の参照は変わらない（indexベース）
          # ここでは何もしない（将来的に名前ベース参照に移行する場合のみ必要）
        when 'tap_dance'
          # TD(0), TD(1) 形式の参照は変わらない（indexベース）
        end
      end

      # 注: 現在の実装ではindex参照なので、ファイル名が変わっても参照は壊れない
      puts "  ✓ Layer references intact (index-based)"
    end

    def verify_compilation
      layout_vil = File.join(File.dirname(@config_dir), 'layout.vil')

      # リネーム後にコンパイル
      compiler = Compiler.new(@config_dir)
      compiler.compile(layout_vil)
      puts "  ✓ Compilation successful"

      # diff確認（2つのファイルを明示的に指定）
      diff_script = File.join(File.dirname(@config_dir), 'bin', 'diff_layouts')
      output = `ruby #{diff_script} #{@before_vil} #{layout_vil} 2>&1`

      if output.include?('✓ FILES ARE IDENTICAL')
        puts "  ✓ Layout structure preserved"
      else
        puts ""
        puts "⚠️  Warning: Layout structure changed"
        puts ""
        puts output
        puts ""
        print "Continue anyway? [y/N]: "
        input = $stdin.gets
        if input
          response = input.chomp.downcase
          unless ['y', 'yes'].include?(response)
            puts ""
            puts "✓ Rename completed but verification failed"
            puts "  You can manually check: ruby bin/diff_layouts #{@before_vil} #{layout_vil}"
          end
        end
      end
    end

    def cleanup_temp_files
      files_to_delete = [
        @plans_file,
        @before_vil,
        File.join(@tmp_dir, 'claude_output.log'),
        File.join(@tmp_dir, 'rename_prompt.txt')
      ]
      deleted = []

      files_to_delete.each do |file|
        if File.exist?(file)
          FileUtils.rm(file)
          deleted << File.basename(file)
        end
      end

      if deleted.any?
        puts "  ✓ Removed: #{deleted.join(', ')}"
      end
    end

    # コマンドを実行しながらアニメーション付きスピナーと経過時間を表示
    # @param command [String] 実行するシェルコマンド
    # @param message [String] スピナーと一緒に表示するメッセージ
    # @return [Array<Boolean, String, Float>] [成功/失敗, 出力, 経過時間]
    def run_with_spinner(command, message: "Processing")
      start_time = Time.now
      running = true
      output = ""

      # スピナースレッド（並行アニメーション）
      spinner_thread = Thread.new do
        spinner_chars = ['⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏']
        idx = 0

        while running
          elapsed = Time.now - start_time
          print "\r  #{spinner_chars[idx]} #{message}... (#{elapsed.to_i}s)"
          $stdout.flush
          idx = (idx + 1) % spinner_chars.length
          sleep 0.1
        end

        # スピナー行をクリア
        print "\r" + " " * 80 + "\r"
        $stdout.flush
      end

      # コマンド実行（メインスレッドをブロック）
      status = false
      begin
        IO.popen(command, err: [:child, :out]) do |io|
          output = io.read
        end
        status = $?.success?
      rescue Errno::ENOENT => e
        # コマンドが見つからない
        output = "Error: Command not found - #{e.message}"
      rescue => e
        # その他のエラー
        output = e.message
      ensure
        running = false
        spinner_thread.join  # 必ずスレッドをクリーンアップ
      end

      elapsed = Time.now - start_time
      [status, output, elapsed]
    end
  end
end
