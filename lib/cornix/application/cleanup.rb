# frozen_string_literal: true

require 'fileutils'
require_relative 'use_case'

module Cornix
  module Application
    # 生成物（config/ と compile の出力 tmp/build/layout.vil）を消す（旧 CliHelpers.cleanup）→ CleanupResult。
    #
    # config/.decompile.lock があるときは force でなければ消さない。force なら confirm.call(lock の内容) が
    # 真のときだけ消す（CLI の y/N）。場所は Environment の root から決まる（旧実装はカレントディレクトリだった）
    class Cleanup < UseCase
      def call(force: false, confirm: nil)
        has_config = File.directory?(env.config_dir)
        has_layout = File.file?(env.layout_path)
        return CleanupResult.new(status: :nothing) unless has_config || has_layout

        lock = env.decompile_lock.read
        if lock
          return CleanupResult.new(status: :protected, lock: lock) unless force
          return CleanupResult.new(status: :cancelled, lock: lock) if confirm && !confirm.call(lock)
        end

        deleted = []
        if has_config
          FileUtils.rm_rf(env.config_dir)
          deleted << 'config/'
        end
        if has_layout
          FileUtils.rm_f(env.layout_path)
          deleted << env.layout_path.delete_prefix("#{env.root}/")
        end
        CleanupResult.new(status: :cleaned, lock: lock, deleted: deleted)
      end
    end
  end
end
