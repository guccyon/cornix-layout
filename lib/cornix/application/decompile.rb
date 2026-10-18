# frozen_string_literal: true

require 'fileutils'
require_relative 'use_case'

module Cornix
  module Application
    # layout.vil → config/（旧 bin/subcommands/decompile.rb + Decompiler）→ DecompileResult。
    #
    # - input を省略すると env.decompile_input（root/tmp/layout.vil）
    # - config/ にすでに設定（layers/ か macros/ の中身）があれば何もしない（:config_exists）
    # - キーの位置は config/position_map.yaml があればそれ、なければテンプレート（lib/cornix/position_map.yaml）で決める。
    #   テンプレートを使ったときは旧実装と同じくテンプレートをそのまま config/ に複写し、
    #   config/ のものを使ったときはそのファイルを元のまま残す
    # - 最後に config/.decompile.lock を書く（cleanup の保護）
    class Decompile < UseCase
      def call(input: nil)
        input = (input || env.decompile_input).to_s
        result = ->(status, **rest) { DecompileResult.new(status: status, input: input, output_dir: env.config_dir, **rest) }
        return result.(:input_missing) unless File.file?(input)
        return result.(:config_exists) if Storage::ConfigFiles.populated?(env.config_dir)

        image = env.vil_file.read(input)
        own = env.repository.position_map_path
        source = own || env.position_map_template
        original = File.read(source, encoding: 'UTF-8')
        profile = env.mapper.to_profile(image, position_map: Storage::ConfigRepository.read_position_map(source))
        FileUtils.mkdir_p(env.config_dir)
        files = env.repository.save(profile)
        restore_position_map(own, original)
        lock = env.decompile_lock.write(source: input)
        result.(:decompiled, files: files, lock: lock, position_map: source)
      end

      private

      # save が書いた position_map.yaml を、元のファイル（なければテンプレート）の内容に戻す
      def restore_position_map(own, original)
        written = File.join(env.config_dir, 'position_map.yaml')
        if own && own != written
          File.delete(written) # 元は position_map.yml（両方あると読み込みで問題になる）
        else
          File.write(written, original)
        end
      end
    end
  end
end
