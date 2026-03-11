# frozen_string_literal: true

require 'yaml'
require 'fileutils'
require 'time'
require 'pathname'
require 'tmpdir'
require_relative 'compiler'
require_relative 'keycode_parser'
require_relative 'converters/reference_converter'

module Cornix
  # YAML設定ファイルのリネームとバックアップを管理するクラス
  #
  # 機能:
  # - インデックスプレフィックスを保持したファイルリネーム
  # - YAML内容（name/description）の更新
  # - 自動バックアップ＆ロールバック
  # - コンパイル検証
  # - トランザクション型バッチ処理
  # - レイヤー参照の自動更新（name-based形式のみ）
  class FileRenamer
    attr_reader :config_dir, :backup_path

    # 初期化
    #
    # @param config_dir [String] 設定ファイルのディレクトリパス（通常は'config'）
    # @param backup_on_init [Boolean] 初期化時にバックアップを作成するか
    # @param skip_compilation_verification [Boolean] コンパイル検証をスキップするか（テスト用）
    def initialize(config_dir, backup_on_init: true, skip_compilation_verification: false)
      @config_dir = File.expand_path(config_dir)
      @backup_path = nil
      @skip_compilation_verification = skip_compilation_verification

      raise ArgumentError, "Config directory not found: #{@config_dir}" unless Dir.exist?(@config_dir)

      # ReferenceConverter を初期化（レイヤー参照の更新用）
      @reference_converter = Converters::ReferenceConverter.new(@config_dir)

      create_backup if backup_on_init
    end

    # 単一ファイルをリネームする
    #
    # @param old_path [String] 元のファイルパス（相対または絶対）
    # @param new_basename [String] 新しいファイル名（ベース名のみ、インデックスプレフィックス含む）
    # @param content_updates [Hash] YAMLフィールドの更新内容（例: { 'name' => '...' }）
    # @return [Hash] 結果ハッシュ { success:, old_path:, new_path:, error: }
    def rename_file(old_path, new_basename, content_updates: {})
      old_path = resolve_path(old_path)

      # ファイル存在チェック
      unless File.exist?(old_path)
        return { success: false, old_path: old_path, new_path: nil, error: "File not found: #{old_path}" }
      end

      # ファイルタイプの検出
      file_type = detect_file_type(old_path)

      # 現在の name フィールドを取得（レイヤー参照更新用）
      old_name = nil
      if file_type && content_updates.key?('name')
        begin
          old_data = YAML.load_file(old_path)
          old_name = old_data['name']
        rescue
          # YAMLパースエラーは無視（後続処理でエラーになる）
        end
      end

      # インデックスプレフィックスの検証
      old_basename = File.basename(old_path)
      expected_prefix = extract_index_prefix(old_basename)

      begin
        validate_new_basename(new_basename, expected_prefix)
      rescue ArgumentError => e
        return { success: false, old_path: old_path, new_path: nil, error: e.message }
      end

      # 新しいパスの構築
      new_path = File.join(File.dirname(old_path), new_basename)

      # 宛先ファイルの重複チェック
      if File.exist?(new_path) && old_path != new_path
        return { success: false, old_path: old_path, new_path: new_path, error: "Destination file already exists: #{new_path}" }
      end

      begin
        # YAML内容の更新（リネーム前に実行）
        update_yaml_content(old_path, content_updates) unless content_updates.empty?

        # ファイルリネーム実行
        File.rename(old_path, new_path) unless old_path == new_path

        # レイヤー参照の更新（name が変更された場合）
        if file_type && old_name && content_updates['name'] && old_name != content_updates['name']
          new_name = content_updates['name']
          updated_layers = update_layer_references(old_name, new_name, file_type)

          # ReferenceConverter のキャッシュをクリア
          @reference_converter.clear_cache

          # デバッグ情報
          puts "  Updated #{updated_layers.size} layer(s) with new reference: #{new_name}" if updated_layers.any?
        end

        { success: true, old_path: old_path, new_path: new_path, error: nil }
      rescue StandardError => e
        { success: false, old_path: old_path, new_path: new_path, error: "Rename failed: #{e.message}" }
      end
    end

    # 一括リネームをトランザクション型で実行する
    #
    # @param rename_plans [Array<Hash>] リネームプランの配列
    #   各要素: { old_path:, new_basename:, content_updates: }
    # @return [Hash] 結果ハッシュ { success:, completed:, failed:, backup_path:, errors: }
    def rename_batch(rename_plans)
      results = {
        success: false,
        completed: [],
        failed: [],
        backup_path: @backup_path,
        errors: []
      }

      # バックアップが未作成の場合は作成
      unless @backup_path
        @backup_path = create_backup
        results[:backup_path] = @backup_path
      end

      # 事前検証
      validation_errors = []
      rename_plans.each_with_index do |plan, idx|
        errors = validate_rename_plan(plan)
        validation_errors.concat(errors.map { |e| "Plan #{idx}: #{e}" }) unless errors.empty?
      end

      unless validation_errors.empty?
        results[:errors] = validation_errors
        results[:failed] = rename_plans
        return results
      end

      # リネーム実行
      rename_plans.each do |plan|
        result = rename_file(
          plan[:old_path] || plan['old_path'],
          plan[:new_basename] || plan['new_basename'],
          content_updates: plan[:content_updates] || plan['content_updates'] || {}
        )

        if result[:success]
          results[:completed] << result
        else
          results[:failed] << { plan: plan, error: result[:error] }
        end
      end

      # 失敗があった場合はロールバック
      if results[:failed].any?
        results[:errors] << "Some renames failed. Rolling back..."
        rollback_success = rollback(@backup_path)
        results[:rollback_completed] = rollback_success
        return results
      end

      # コンパイル検証
      unless @skip_compilation_verification
        verification = verify_compilation
        unless verification[:success]
          results[:errors] << "Compilation verification failed: #{verification[:error]}"
          results[:errors] << "Rolling back..."
          rollback_success = rollback(@backup_path)
          results[:rollback_completed] = rollback_success
          return results
        end
      end

      # すべて成功
      results[:success] = true
      results
    end

    # バックアップを作成する
    #
    # @param timestamp [String] タイムスタンプ文字列（省略時は現在時刻）
    # @return [String] バックアップディレクトリのパス
    def create_backup(timestamp = Time.now.strftime('%Y%m%d_%H%M%S'))
      backup_dir = "#{@config_dir}.backup_#{timestamp}"

      # 既存のバックアップがある場合はエラー
      if Dir.exist?(backup_dir)
        raise "Backup directory already exists: #{backup_dir}"
      end

      # config/ ディレクトリ全体をコピー
      FileUtils.cp_r(@config_dir, backup_dir)

      # マニフェストファイルを作成
      manifest = {
        'timestamp' => timestamp,
        'source_dir' => @config_dir,
        'backup_dir' => backup_dir,
        'files_count' => Dir.glob("#{backup_dir}/**/*").select { |f| File.file?(f) }.size
      }
      File.write(File.join(backup_dir, '.backup_manifest.yaml'), YAML.dump(manifest))

      @backup_path = backup_dir
      backup_dir
    end

    # ロールバックを実行する
    #
    # @param backup_path [String] バックアップディレクトリのパス（省略時は@backup_path）
    # @return [Boolean] 成功したかどうか
    def rollback(backup_path = @backup_path)
      return false unless backup_path && Dir.exist?(backup_path)

      begin
        # 現在のconfig/を削除
        FileUtils.rm_rf(@config_dir)

        # バックアップから復元（バックアップディレクトリの内容をconfig/にコピー）
        FileUtils.mkdir_p(@config_dir)
        Dir.glob("#{backup_path}/*", File::FNM_DOTMATCH).each do |item|
          next if File.basename(item) == '.' || File.basename(item) == '..'
          FileUtils.cp_r(item, @config_dir)
        end

        # マニフェストファイルを削除（復元したconfig/内に含まれている）
        manifest_path = File.join(@config_dir, '.backup_manifest.yaml')
        FileUtils.rm_f(manifest_path) if File.exist?(manifest_path)

        true
      rescue StandardError => e
        warn "Rollback failed: #{e.message}"
        false
      end
    end

    # コンパイル検証を実行する
    #
    # @return [Hash] 結果ハッシュ { success:, error:, backtrace: }
    def verify_compilation
      # 一時ファイルにコンパイル
      temp_output = File.join(Dir.tmpdir, "verify_#{Process.pid}.vil")

      begin
        compiler = Compiler.new(@config_dir)
        compiler.compile(temp_output)

        { success: true, error: nil }
      rescue StandardError => e
        { success: false, error: e.message, backtrace: e.backtrace }
      ensure
        # 一時ファイルをクリーンアップ
        FileUtils.rm_f(temp_output) if temp_output && File.exist?(temp_output)
      end
    end

    # バックアップディレクトリをクリーンアップする
    #
    # @param backup_path [String] バックアップディレクトリのパス（省略時は@backup_path）
    # @return [Boolean] 成功したかどうか
    def cleanup_backup(backup_path = @backup_path)
      return false unless backup_path && Dir.exist?(backup_path)

      begin
        FileUtils.rm_rf(backup_path)
        @backup_path = nil if backup_path == @backup_path
        true
      rescue StandardError => e
        warn "Backup cleanup failed: #{e.message}"
        false
      end
    end

    # レイヤーファイル内のname-based参照を更新する
    #
    # @param old_name [String] 古い名前
    # @param new_name [String] 新しい名前
    # @param type [Symbol] ファイルタイプ (:macro, :tap_dance, :combo)
    # @return [Array<String>] 更新されたレイヤーファイルのパスの配列
    def update_layer_references(old_name, new_name, type)
      function_name = case type
      when :macro then 'Macro'
      when :tap_dance then 'TapDance'
      when :combo then 'Combo'
      else
        return []
      end

      updated_files = []

      Dir.glob("#{@config_dir}/layers/*.{yaml,yml}").each do |layer_file|
        begin
          layer_data = YAML.load_file(layer_file)
          mapping = layer_data['mapping'] || layer_data['overrides'] || {}

          changed = false
          mapping.each do |symbol, keycode|
            # Parse using KeycodeParser
            parsed = KeycodeParser.parse(keycode.to_s)

            # Only update name-based references (not index-based or legacy)
            if parsed[:type] == :reference &&
               parsed[:function] == function_name &&
               parsed[:args][0][:type] == :string &&
               parsed[:args][0][:value] == old_name

              # Update to new name
              new_token = {
                type: :reference,
                function: function_name,
                args: [{ type: :string, value: new_name }]
              }
              mapping[symbol] = KeycodeParser.unparse(new_token)
              changed = true
            end
          end

          if changed
            File.write(layer_file, YAML.dump(layer_data))
            updated_files << layer_file
          end
        rescue => e
          warn "Warning: Failed to update references in #{layer_file}: #{e.message}"
        end
      end

      updated_files
    end

    # ファイルタイプを検出する
    #
    # @param file_path [String] ファイルパス
    # @return [Symbol, nil] ファイルタイプ (:macro, :tap_dance, :combo) または nil
    def detect_file_type(file_path)
      case file_path
      when %r{/macros/}
        :macro
      when %r{/tap_dance/}
        :tap_dance
      when %r{/combos/}
        :combo
      else
        nil
      end
    end

    private

    # ファイルパスを解決する（相対パスを絶対パスに変換）
    def resolve_path(path)
      path_obj = Pathname.new(path)

      # 既に絶対パスの場合はそのまま返す
      return path if path_obj.absolute?

      # 相対パスの場合、config_dirからの相対として解決
      expanded_path = File.expand_path(path, Dir.pwd)

      # パスが既にconfig_dirで始まる場合はそのまま返す
      # （例: config/macros/... は /path/to/config/macros/... に展開される）
      if expanded_path.start_with?(@config_dir)
        expanded_path
      else
        # config_dirからの相対パスとして解決
        File.join(@config_dir, path)
      end
    end

    # ファイル名からインデックスプレフィックスを抽出する
    #
    # @param basename [String] ファイル名（例: '03_macro.yml'）
    # @return [String, nil] インデックスプレフィックス（例: '03_'）、なければnil
    def extract_index_prefix(basename)
      match = basename.match(/^(\d+_)/)
      match ? match[1] : nil
    end

    # 新しいファイル名のインデックスプレフィックスを検証する
    #
    # @param new_basename [String] 新しいファイル名
    # @param expected_prefix [String, nil] 期待されるインデックスプレフィックス
    # @raise [ArgumentError] インデックスが一致しない場合
    def validate_new_basename(new_basename, expected_prefix)
      actual_prefix = extract_index_prefix(new_basename)

      if expected_prefix && actual_prefix != expected_prefix
        raise ArgumentError, "Index prefix mismatch: expected '#{expected_prefix}', got '#{actual_prefix || 'none'}'"
      end

      if !expected_prefix && actual_prefix
        raise ArgumentError, "Unexpected index prefix: '#{actual_prefix}'"
      end
    end

    # YAMLファイルの内容を更新する
    #
    # @param file_path [String] YAMLファイルのパス
    # @param updates [Hash] 更新するフィールド（例: { 'name' => '...' }）
    def update_yaml_content(file_path, updates)
      return if updates.empty?

      begin
        data = YAML.load_file(file_path)

        # ハッシュでない場合はエラー
        unless data.is_a?(Hash)
          raise "Invalid YAML structure: expected Hash, got #{data.class}"
        end

        # フィールドを更新
        updates.each do |key, value|
          data[key.to_s] = value
        end

        # ファイルに書き戻し
        File.write(file_path, YAML.dump(data))
      rescue StandardError => e
        raise "Failed to update YAML content: #{e.message}"
      end
    end

    # リネームプランを検証する
    #
    # @param plan [Hash] リネームプラン { old_path:, new_basename:, content_updates: }
    # @return [Array<String>] エラーメッセージの配列（空なら検証成功）
    def validate_rename_plan(plan)
      errors = []

      # 必須フィールドのチェック
      old_path = plan[:old_path] || plan['old_path']
      new_basename = plan[:new_basename] || plan['new_basename']

      errors << "Missing 'old_path' field" unless old_path
      errors << "Missing 'new_basename' field" unless new_basename

      return errors if errors.any?

      # ファイル存在チェック
      old_path = resolve_path(old_path)
      errors << "File not found: #{old_path}" unless File.exist?(old_path)

      return errors if errors.any?

      # インデックスプレフィックスの検証
      old_basename = File.basename(old_path)
      expected_prefix = extract_index_prefix(old_basename)

      begin
        validate_new_basename(new_basename, expected_prefix)
      rescue ArgumentError => e
        errors << e.message
      end

      # 宛先ファイルの重複チェック
      new_path = File.join(File.dirname(old_path), new_basename)
      if File.exist?(new_path) && old_path != new_path
        errors << "Destination file already exists: #{new_path}"
      end

      # YAML構文チェック
      begin
        YAML.load_file(old_path)
      rescue Psych::SyntaxError => e
        errors << "Invalid YAML syntax: #{e.message}"
      end

      errors
    end
  end
end
