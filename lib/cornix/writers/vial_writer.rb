# frozen_string_literal: true

require 'json'

module Cornix
  module Writers
    # VialWriter - VialConfig → layout.vil (JSON)
    class VialWriter
      # VialConfig を JSON として layout.vil に書き込み
      def write(vial_config, output_path, position_map:, keycode_converter:, reference_converter:)
        qmk_hash = vial_config.to_qmk(
          position_map: position_map,
          keycode_converter: keycode_converter,
          reference_converter: reference_converter
        )

        json_content = JSON.pretty_generate(qmk_hash)
        File.write(output_path, json_content)
      end
    end
  end
end
