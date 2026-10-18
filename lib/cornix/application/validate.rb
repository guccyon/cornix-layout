# frozen_string_literal: true

require_relative 'use_case'

module Cornix
  module Application
    # 設定ディレクトリを検証する → ValidationReport（旧 ModelValidator#validate）。
    #
    # 1. 構造検証: ConfigRepository#load（YAML の文法、形、キーコード、ファイル名の番号など）。問題はすべて errors
    # 2. 意味検証: Profile#diagnostics(env.capabilities)（参照先、件数の上限、名前の重複、Cornix が対応していないキーなど）。位置は ConfigRepository#locate で
    #    「ファイル: キーの位置」にし、severity に応じて errors / warnings に分ける
    # 設定ディレクトリがなければ ConfigNotFound
    class Validate < UseCase
      def call
        raise ConfigNotFound, env.config_dir unless File.directory?(env.config_dir)

        profile = env.repository.load
        located = profile.diagnostics(env.capabilities).map { |d| env.repository.locate(d) }
        ValidationReport.new(errors: located.select(&:error?).map { |d| text(d) },
                             warnings: located.select(&:warning?).map { |d| text(d) }, profile: profile)
      rescue Storage::InvalidConfig => e
        ValidationReport.new(errors: e.problems.map(&:to_s))
      end

      private

      def text(diagnostic) = [diagnostic.path, diagnostic.message].reject(&:empty?).join(': ')
    end
  end
end
