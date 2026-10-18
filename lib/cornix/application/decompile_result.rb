# frozen_string_literal: true

module Cornix
  module Application
    # Decompile の結果。status は
    #   :decompiled     書いた（files は書いたファイルの相対パス、lock は .decompile.lock のパス）
    #   :input_missing  入力の .vil がない
    #   :config_exists  config/ にすでに設定がある（layers/ か macros/ が空でない）ので何もしなかった
    class DecompileResult < Data.define(:status, :input, :output_dir, :files, :lock, :position_map)
      def initialize(status:, input:, output_dir:, files: [], lock: nil, position_map: nil) = super

      def decompiled? = status == :decompiled
    end
  end
end
