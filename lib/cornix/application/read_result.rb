# frozen_string_literal: true

module Cornix
  module Application
    # DeviceRead の結果。vil は layout.vil 形式の JSON 文字列、path は保存したとき保存先（しなければ nil）
    class ReadResult < Data.define(:image, :vil, :path)
      def to_h = { 'path' => path, 'vil' => vil }
    end
  end
end
