# frozen_string_literal: true

require 'digest'

module Cornix
  module Storage
    # ファイルの中身の版（protocol.md の FileVersion）。ディスク上のバイト列そのものの SHA-256 で、改行や BOM は正規化しない。
    #
    #   FileVersion.of(File.binread(path))   # => "sha256:9f2c…"（小文字の 16 進）
    #   FileVersion.of(nil)                   # => nil（ファイルがない）
    #   FileVersion.read(path)                # => ファイルの版。なければ nil
    module FileVersion
      PREFIX = 'sha256:'

      module_function

      def of(bytes) = bytes && "#{PREFIX}#{Digest::SHA256.hexdigest(bytes.b)}"

      def read(path) = File.file?(path) ? of(File.binread(path)) : nil
    end
  end
end
