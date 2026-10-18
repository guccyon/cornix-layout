# frozen_string_literal: true

require_relative 'use_case'

module Cornix
  module Application
    # config/ → layout.vil（旧 bin/subcommands/compile.rb + Compiler）→ CompileResult。
    # 先に Validate し、errors があれば何も書かない（warnings だけなら書く）。
    # output を省略すると env.layout_path に書く
    class Compile < UseCase
      def call(output: nil)
        report = Validate.new(env).call
        return CompileResult.new(report: report) unless report.valid?

        image = env.mapper.to_image(report.profile)
        path = env.vil_file.write(image, output || env.layout_path)
        CompileResult.new(report: report, path: path, image: image)
      end
    end
  end
end
