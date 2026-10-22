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
    #
    # 使えないときは Cornix::DeviceUnavailable（reason で理由を見分ける）: macOS でない（:platform）、
    # ブリッジをビルド・起動できない（:bridge）、キーボードが見つからない・開けない（:not_connected）、
    # 通信中に応答がない・ブリッジが終わった（:timeout）。ブリッジが送信を拒否したときはただの DeviceError
    class HidBridge
      MSG_LEN = 32
      ROOT = File.expand_path('../../..', __dir__)
      SOURCE = File.join(ROOT, 'ext', 'cornix_hid', 'main.swift')
      BINARY = File.join(ROOT, 'tmp', 'cornix-hid')

      attr_reader :info

      # ブリッジが送信を拒否した・行の形が違う（通信の失敗ではない）ときのブリッジの文の先頭
      REFUSED = /\A(拒否|不正な行)/

      def self.build!
        return BINARY if File.exist?(BINARY) && File.mtime(BINARY) >= File.mtime(SOURCE)

        FileUtils.mkdir_p(File.dirname(BINARY))
        out, status = begin
          Open3.capture2e('swiftc', '-O', SOURCE, '-o', BINARY)
        rescue SystemCallError => e
          raise DeviceUnavailable.new("cornix-hid をビルドできません（swiftc が使えません: #{e.message}）。" \
                                      'Xcode の Command Line Tools を入れてください', reason: :bridge)
        end
        unless status.success?
          raise DeviceUnavailable.new("cornix-hid のビルドに失敗しました:\n#{out.force_encoding('UTF-8')}", reason: :bridge)
        end

        BINARY
      end

      def self.macos? = RUBY_PLATFORM.include?('darwin')

      def self.open
        # CORNIX_HID_BRIDGE でブリッジを差し替えられる（テスト用）
        override = ENV.fetch('CORNIX_HID_BRIDGE', nil)
        if override.nil? && !macos?
          raise DeviceUnavailable.new('キーボードとの通信は macOS でだけ使えます', reason: :platform)
        end

        bridge = new(override || build!)
        return bridge unless block_given?

        begin
          yield bridge
        ensure
          bridge.close
        end
      end

      def initialize(binary)
        begin
          @stdin, @stdout, @wait = Open3.popen2(binary)
        rescue SystemCallError => e
          raise DeviceUnavailable.new("cornix-hid を起動できません: #{e.message}", reason: :bridge)
        end
        line = @stdout.gets&.force_encoding('UTF-8')
        raise DeviceUnavailable.new('cornix-hid が応答しません', reason: :bridge) if line.nil?

        tag, rest = line.chomp.split(' ', 2)
        unless tag == 'READY'
          close
          raise DeviceUnavailable.new(rest || line, reason: :not_connected)
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
          raise DeviceUnavailable.new('cornix-hid が終了しました', reason: :timeout)
        end
        line = @stdout.gets&.force_encoding('UTF-8')
        raise DeviceUnavailable.new('cornix-hid が終了しました', reason: :timeout) if line.nil?

        tag, rest = line.chomp.split(' ', 2)
        unless tag == 'RECV'
          raise DeviceError, rest.to_s if REFUSED.match?(rest.to_s)

          raise DeviceUnavailable.new(rest.to_s, reason: :timeout)
        end

        [rest].pack('H*').bytes
      end

      def close
        @stdin&.close unless @stdin&.closed?
        @wait&.value
      end
    end
  end
end
