#!/usr/bin/env ruby
# frozen_string_literal: true

require 'json'
require_relative '../../lib/cornix/device/keyboard'

# Parse arguments (ARGV has already had the command removed by bin/cornix)
action = ARGV.shift
default_vil = File.expand_path('../../layout.vil', __dir__)

def print_diff(keyboard, result)
  if result[:changes].empty?
    puts '✓ キーボードとの差分はありません'
  else
    puts "差分 #{result[:changes].size} 件:"
    result[:changes].each { |ch| puts "  - #{keyboard.format_change(ch)}" }
  end
  result[:warnings].each { |w| puts "  ⚠️  #{w}" }
end

begin
  case action
  when 'info'
    Cornix::Device::Keyboard.open { |kb| puts JSON.pretty_generate(kb.info) }
  when 'read'
    output = ARGV.index('-o') ? ARGV[ARGV.index('-o') + 1] : nil
    Cornix::Device::Keyboard.open do |kb|
      json = JSON.pretty_generate(kb.snapshot)
      if output
        File.write(output, json)
        puts "✓ 保存しました: #{output}"
      else
        puts json
      end
    end
  when 'backup'
    Cornix::Device::Keyboard.open { |kb| puts "✓ バックアップを保存しました: #{kb.backup}" }
  when 'diff'
    vil = ARGV[0] || default_vil
    target = JSON.parse(File.read(vil))
    Cornix::Device::Keyboard.open { |kb| print_diff(kb, kb.diff(target)) }
  when 'apply'
    yes = ARGV.delete('--yes')
    vil = ARGV[0] || default_vil
    target = JSON.parse(File.read(vil))
    Cornix::Device::Keyboard.open do |kb|
      result = kb.diff(target)
      print_diff(kb, result)
      next if result[:changes].empty?

      unless yes
        print "\nこの差分をキーボードに書き込みますか？ [y/N] "
        answer = $stdin.gets.to_s.strip.downcase
        unless %w[y yes].include?(answer)
          puts '中止しました'
          next
        end
      end
      applied = kb.apply(target, expected_token: result[:token])
      puts "✓ #{applied[:applied]} 件を書き込みました（反映前のバックアップ: #{applied[:backup]}）"
      if applied[:remaining].empty?
        puts '✓ 読み戻して検証し、すべて一致しました'
      else
        puts "⚠️  読み戻し後も #{applied[:remaining].size} 件が一致しません:"
        applied[:remaining].each { |ch| puts "  - #{kb.format_change(ch)}" }
        exit 1
      end
    end
  else
    puts <<~USAGE
      Usage:
        cornix device info              接続中のキーボードの情報を表示
        cornix device read [-o FILE]    キーボードの状態を layout.vil 形式で出力
        cornix device backup            キーボードの状態を tmp/device_backups/ に保存
        cornix device diff [FILE]       layout.vil とキーボードの差分を表示（書き込みなし）
        cornix device apply [FILE]      差分を確認してキーボードへ書き込む（--yes で確認を省略）
    USAGE
    exit(action.nil? ? 0 : 1)
  end
rescue Cornix::Device::DeviceError, Errno::ENOENT, JSON::ParserError => e
  puts "Error: #{e.message}"
  exit 1
end
