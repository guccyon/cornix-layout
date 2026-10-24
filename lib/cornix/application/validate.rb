# frozen_string_literal: true

require_relative 'use_case'

module Cornix
  module Application
    # 設定ディレクトリを検証する → ValidationReport（旧 ModelValidator#validate）。
    #
    # 1. 構造検証: ConfigRepository#load_all（YAML の文法、形、キーコードなど）。問題はすべて error
    # 2. 意味検証: Profile#diagnostics(env.capabilities)（参照先、件数の上限、名前の重複、Cornix が対応していないキーなど）。位置は ConfigRepository#locate で
    #    「ファイル: キーの位置」にする
    # 未使用のファイル（index のないもの。issue #85）は意味検証の対象外で、構造の問題は warning にする（compile を止めない）。
    # 一覧は ValidationReport#unused
    # 設定ディレクトリがなければ ConfigNotFound
    class Validate < UseCase
      UNUSED_NOTE = '（未使用のファイルなので compile に含めません）'

      def call
        raise ConfigNotFound, env.config_dir unless File.directory?(env.config_dir)

        loaded = env.repository.load_all
        located = loaded.profile.diagnostics(env.capabilities).map { |d| env.repository.locate(d) }
        ValidationReport.new(diagnostics: located + unused_warnings(loaded.unused), profile: loaded.profile,
                             unused: loaded.unused)
      rescue Storage::InvalidConfig => e
        ValidationReport.new(diagnostics: e.problems.map { |problem| structure(problem) } + unused_warnings(e.unused),
                             unused: e.unused)
      end

      private

      # Storage::Problem → Domain::Diagnostic（path は「ファイル: キーの位置」。空の部分は省く）
      def structure(problem, severity = :error)
        path = [problem.file, problem.location].reject { |s| s.nil? || s.empty? }.join(': ')
        Domain::Diagnostic.new(severity: severity, path: path, message: problem.message)
      end

      def unused_warnings(unused)
        unused.flat_map(&:problems).map { |problem| structure(problem.with(message: problem.message + UNUSED_NOTE), :warning) }
      end
    end
  end
end
