# frozen_string_literal: true

module Cornix
  module Application
    # ListBackups の結果（バックアップのパスを新しい順に）
    class BackupList < Data.define(:dir, :paths)
      def initialize(dir:, paths:) = super(dir: dir, paths: paths.dup.freeze)

      def empty? = paths.empty?
      def to_h = { 'dir' => dir, 'backups' => paths.dup }
    end
  end
end
