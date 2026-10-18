# frozen_string_literal: true

module Cornix
  module Application
    # Compile の結果。report は検証の結果、path は書いた .vil（検証に失敗して書かなかったら nil）
    class CompileResult < Data.define(:report, :path, :image)
      def initialize(report:, path: nil, image: nil) = super

      def compiled? = !path.nil?
    end
  end
end
