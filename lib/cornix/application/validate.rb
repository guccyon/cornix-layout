# frozen_string_literal: true

require_relative 'use_case'

module Cornix
  module Application
    # 設定ディレクトリを検証する → ValidationReport（旧 ModelValidator#validate）。
    #
    # 1. 構造検証: ConfigRepository#load（YAML の文法、形、キーコード、ファイル名の番号など）。問題はすべて error
    # 2. 意味検証: Profile#diagnostics(env.capabilities)（参照先、件数の上限、名前の重複、Cornix が対応していないキーなど）。位置は ConfigRepository#locate で
    #    「ファイル: キーの位置」にする
    # 設定ディレクトリがなければ ConfigNotFound
    class Validate < UseCase
      def call
        raise ConfigNotFound, env.config_dir unless File.directory?(env.config_dir)

        profile = env.repository.load
        located = profile.diagnostics(env.capabilities).map { |d| env.repository.locate(d) }
        ValidationReport.new(diagnostics: located, profile: profile)
      rescue Storage::InvalidConfig => e
        ValidationReport.new(diagnostics: e.problems.map { |problem| structure(problem) })
      end

      private

      # Storage::Problem → Domain::Diagnostic（path は「ファイル: キーの位置」。空の部分は省く）
      def structure(problem)
        path = [problem.file, problem.location].reject { |s| s.nil? || s.empty? }.join(': ')
        Domain::Diagnostic.error(path, problem.message)
      end
    end
  end
end
