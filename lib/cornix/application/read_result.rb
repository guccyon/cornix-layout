# frozen_string_literal: true

require 'json'

module Cornix
  module Application
    # DeviceRead の結果。vil は layout.vil 形式の JSON 文字列、path は保存したとき保存先（しなければ nil）。
    # to_h の vil は JSON として読んだもの（文字列のまま埋め込まない）。保存したときは中身を返さない（path だけ）
    class ReadResult < Data.define(:image, :vil, :path)
      def to_h = path ? { 'path' => path } : { 'path' => nil, 'vil' => JSON.parse(vil) }
    end
  end
end
