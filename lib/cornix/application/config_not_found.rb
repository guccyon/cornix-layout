# frozen_string_literal: true

module Cornix
  module Application
    # 設定ディレクトリ（config/）がない（compile / validate / rename の前提）
    class ConfigNotFound < Cornix::ConfigError
      attr_reader :dir

      def initialize(dir)
        @dir = dir
        super('設定ディレクトリがありません', path: dir)
      end
    end
  end
end
