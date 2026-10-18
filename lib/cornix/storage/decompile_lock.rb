# frozen_string_literal: true

require 'yaml'
require 'digest'
require_relative 'yaml_file'

module Cornix
  module Storage
    # decompile が設定ディレクトリに置くロックファイル（config/.decompile.lock）。
    # cleanup はこれがあると -f なしでは消さない。形式は旧 bin/subcommands/decompile.rb と同じ:
    #
    #   decompiled_at: 2026-10-18 12:00:00 +0900
    #   source_file: /path/to/layout.vil
    #   checksum: <SHA256>
    class DecompileLock
      FILE = '.decompile.lock'

      def initialize(config_dir)
        @path = File.join(config_dir.to_s, FILE)
      end

      attr_reader :path

      def exist? = File.file?(@path)

      # 内容の Hash（読めなければ空の Hash）。ロックがなければ nil
      def read
        return nil unless exist?

        data = YamlFile.read(@path)
        data.is_a?(Hash) ? data : {}
      rescue YamlFile::Unreadable
        {}
      end

      # source（decompile した .vil）の情報を書いてパスを返す
      def write(source:, time: Time.now)
        content = { 'decompiled_at' => time.to_s, 'source_file' => source.to_s,
                    'checksum' => Digest::SHA256.file(source).hexdigest }
        File.write(@path, content.to_yaml)
        @path
      end
    end
  end
end
