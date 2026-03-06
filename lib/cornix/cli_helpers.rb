# frozen_string_literal: true

require 'yaml'
require 'digest'
require 'fileutils'

module Cornix
  module CliHelpers
    # Check if config directory has existing files and block if necessary
    def self.check_config_lock(config_dir)
      if File.exist?(config_dir) && Dir.exist?(config_dir)
        has_layers = Dir.exist?("#{config_dir}/layers") && !Dir.empty?("#{config_dir}/layers")
        has_macros = Dir.exist?("#{config_dir}/macros") && !Dir.empty?("#{config_dir}/macros")

        if has_layers || has_macros
          puts "⚠️  Error: config/ directory already contains configuration files."
          puts ""
          puts "To protect your existing configuration, decompile has been blocked."
          puts ""
          puts "Options:"
          puts "  1. Backup your config/ directory and remove it"
          puts "  2. Use 'cornix compile' to compile existing config"
          puts ""
          puts "Example:"
          puts "  mv config config.backup"
          puts "  cornix decompile ~/Downloads/layout.vil"
          exit 1
        end
      end
    end

    # Ensure config directory exists, with optional custom error message
    def self.ensure_config_exists(config_dir, &custom_message)
      unless Dir.exist?(config_dir)
        puts "Error: #{config_dir} not found"
        custom_message.call if custom_message
        exit 1
      end
    end

    # Clean up generated files (config/, layout.vil)
    def self.cleanup(force = false)
      config_dir = File.expand_path('config', Dir.pwd)
      layout_vil = File.expand_path('layout.vil', Dir.pwd)
      lock_file = "#{config_dir}/.decompile.lock"

      # 削除対象の存在チェック
      has_config = Dir.exist?(config_dir)
      has_layout = File.exist?(layout_vil)
      has_lock = File.exist?(lock_file)

      # 何も削除するものがない場合
      unless has_config || has_layout
        puts "✓ Nothing to clean up"
        return
      end

      # lockファイル保護チェック
      if has_lock && !force
        # lockファイル情報を表示
        lock_data = YAML.load_file(lock_file)
        puts "⚠️  Protected: config/ directory has an active lock file"
        puts ""
        puts "Lock file details:"
        puts "  Created: #{lock_data['decompiled_at']}"
        puts "  Source: #{lock_data['source_file']}"
        puts "  Checksum: #{lock_data['checksum'][0..15]}..."
        puts ""
        puts "To force cleanup (deletes lock file too):"
        puts "  cornix cleanup -f"
        exit 1
      end

      # 強制実行時の確認プロンプト
      if force && has_lock
        lock_data = YAML.load_file(lock_file)
        puts "⚠️  WARNING: This will delete all config files and the lock file"
        puts ""
        puts "Lock file details:"
        puts "  Created: #{lock_data['decompiled_at']}"
        puts "  Source: #{lock_data['source_file']}"
        puts ""
        print "Are you sure you want to continue? [y/N]: "
        confirmation = $stdin.gets.chomp.downcase

        unless ['y', 'yes'].include?(confirmation)
          puts "✓ Cleanup cancelled"
          exit 0
        end
      end

      # クリーンアップ実行
      deleted_items = []

      if has_config
        FileUtils.rm_rf(config_dir)
        deleted_items << "config/"
      end

      if has_layout
        FileUtils.rm(layout_vil)
        deleted_items << "layout.vil"
      end

      puts "✓ Cleanup completed"
      puts ""
      puts "Deleted:"
      deleted_items.each { |item| puts "  - #{item}" }
      puts ""
      puts "You can now run 'cornix decompile' to generate fresh config files"
    end
  end
end
