# frozen_string_literal: true

require 'open3'
require 'json'
require 'fileutils'
require_relative '../errors'

module Cornix
  module Device
    # ext/cornix_hid/main.swift（macOS の IOKit で raw HID を扱う小さなブリッジ）を
    # 子プロセスとして起動し、32 バイトのレポートを送受信する。
    #
    # 送信できるコマンドはブリッジ側でも許可リストで制限している（bootloader 移行や
    # EEPROM リセットなどはブリッジが拒否する）。
    class HidBridge
      MSG_LEN = 32
      ROOT = File.expand_path('../../..', __dir__)
      SOURCE = File.join(ROOT, 'ext', 'cornix_hid', 'main.swift')
      BINARY = File.join(ROOT, 'tmp', 'cornix-hid')

      attr_reader :info

      def self.build!
        return BINARY if File.exist?(BINARY) && File.mtime(BINARY) >= File.mtime(SOURCE)

        FileUtils.mkdir_p(File.dirname(BINARY))
        out, status = Open3.capture2e('swiftc', '-O', SOURCE, '-o', BINARY)
        raise DeviceError, "cornix-hid のビルドに失敗しました:\n#{out.force_encoding('UTF-8')}" unless status.success?

        BINARY
      end

      def self.open
        # CORNIX_HID_BRIDGE でブリッジを差し替えられる（テスト用）
        bridge = new(ENV['CORNIX_HID_BRIDGE'] || build!)
        return bridge unless block_given?

        begin
          yield bridge
        ensure
          bridge.close
        end
      end

      def initialize(binary)
        @stdin, @stdout, @wait = Open3.popen2(binary)
        line = @stdout.gets&.force_encoding('UTF-8')
        raise DeviceError, 'cornix-hid が応答しません' if line.nil?

        tag, rest = line.chomp.split(' ', 2)
        unless tag == 'READY'
          close
          raise DeviceError, rest || line
        end
        @info = JSON.parse(rest)
      end

      # bytes: 32 バイト以下の整数配列（不足分は 0 で埋める）→ 応答 32 バイト
      def transfer(bytes)
        raise ArgumentError, "メッセージは #{MSG_LEN} バイト以下" if bytes.size > MSG_LEN

        msg = bytes + [0] * (MSG_LEN - bytes.size)
        begin
          @stdin.puts("SEND #{msg.pack('C*').unpack1('H*')}")
          @stdin.flush
        rescue Errno::EPIPE, IOError
          # ブリッジが先に終了していると書き込みの時点で失敗する
          raise DeviceError, 'cornix-hid が終了しました'
        end
        line = @stdout.gets&.force_encoding('UTF-8')
        raise DeviceError, 'cornix-hid が終了しました' if line.nil?

        tag, rest = line.chomp.split(' ', 2)
        raise DeviceError, rest unless tag == 'RECV'

        [rest].pack('H*').bytes
      end

      def close
        @stdin&.close unless @stdin&.closed?
        @wait&.value
      end
    end
  end
end
