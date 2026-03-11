# frozen_string_literal: true

require 'json'
require_relative '../models/vial_config'

module Cornix
  module Loaders
    # VialLoader - layout.vil (JSON) → VialConfig
    class VialLoader
      def initialize(vil_path)
        @vil_path = vil_path
      end

      # layout.vil を読み込んで VialConfig に変換
      def load(position_map:, keycode_converter:, reference_converter: nil)
        unless File.exist?(@vil_path)
          raise "File not found: #{@vil_path}"
        end

        json_content = File.read(@vil_path)
        qmk_hash = JSON.parse(json_content)

        Models::VialConfig.from_qmk(qmk_hash, position_map, keycode_converter, reference_converter: reference_converter)
      end
    end
  end
end
