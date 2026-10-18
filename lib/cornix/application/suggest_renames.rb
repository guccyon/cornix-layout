# frozen_string_literal: true

require 'json'
require 'fileutils'
require_relative 'use_case'

module Cornix
  module Application
    # 既定の名前（"Macro 3" など）のファイルに付ける名前を Claude に提案してもらう（旧 RenameCommand の Step 2）。
    #
    #   suggest = SuggestRenames.new(env)
    #   result = suggest.call                 # => RenameSuggestions（plans は RenamePlan の配列）
    #   result = suggest.load_plans           # 手で書いた tmp/rename_plans.json を読む（Claude が使えないとき）
    #   suggest.cleanup                       # tmp/ の一時ファイルを消す → 消したファイル名
    #
    # 一時ファイル: tmp/rename_plans.json（計画）、tmp/claude_output.log（Claude の出力）
    class SuggestRenames < UseCase
      PLANS_FILE = 'rename_plans.json'
      LOG_FILE = 'claude_output.log'
      TEMP_FILES = [PLANS_FILE, LOG_FILE, 'rename_prompt.txt', 'layout_before_rename.vil'].freeze
      KINDS = %i[macros tap_dances combos layers].freeze

      def available? = env.claude.available?
      def plans_path = File.join(env.tmp_dir, PLANS_FILE)
      def log_path = File.join(env.tmp_dir, LOG_FILE)

      def call(clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
        FileUtils.mkdir_p(env.tmp_dir)
        FileUtils.rm_f(plans_path)
        return RenameSuggestions.new(status: :claude_missing) unless env.claude.available?

        started = clock.call
        success, output = env.claude.run(prompt)
        elapsed = clock.call - started
        File.write(log_path, output)
        json = RenamePrompt.extract_json(output)
        unless json
          return RenameSuggestions.new(status: :unparsed, elapsed: elapsed, success: success, log_path: log_path,
                                       plans_path: plans_path)
        end

        File.write(plans_path, json)
        load_plans.with(elapsed: elapsed, success: success, log_path: log_path)
      end

      # プロンプト（設定ファイルの中身を含む）
      def prompt
        files = KINDS.to_h do |kind|
          rels = Storage::ConfigFiles.list(env.config_dir, kind)
          [kind, rels.map { |rel| [display_path(rel), File.read(File.join(env.config_dir, rel), encoding: 'UTF-8')] }]
        end
        RenamePrompt.build(files)
      end

      def load_plans(path = plans_path)
        return RenameSuggestions.new(status: :missing, plans_path: path) unless File.file?(path)

        data = JSON.parse(File.read(path, encoding: 'UTF-8'))
        raise JSON::ParserError, 'JSON の配列ではありません' unless data.is_a?(Array) && data.all?(Hash)

        plans = data.map do |h|
          RenamePlan.from_h({ 'reasoning' => 'Suggested by Claude AI', 'confidence' => 'high' }.merge(h.compact))
        end
        RenameSuggestions.new(status: :ok, plans: plans, plans_path: path)
      rescue JSON::ParserError => e
        RenameSuggestions.new(status: :invalid, plans_path: path, error: e.message)
      end

      # 一時ファイルを消して、消したファイル名を返す
      def cleanup
        TEMP_FILES.map { |name| File.join(env.tmp_dir, name) }.select { |p| File.file?(p) }.map do |path|
          File.delete(path)
          File.basename(path)
        end
      end

      private

      # root の下なら root からの相対パス（config/macros/00_macro.yml）
      def display_path(rel)
        path = File.join(env.config_dir, rel)
        path.start_with?("#{env.root}/") ? path.delete_prefix("#{env.root}/") : path
      end
    end
  end
end
