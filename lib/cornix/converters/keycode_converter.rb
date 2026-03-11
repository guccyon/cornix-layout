# frozen_string_literal: true

require 'yaml'

module Cornix
  module Converters
    # キーコードエイリアスの解決を担当
    class KeycodeConverter
      def initialize(yaml_path)
        @data = YAML.load_file(yaml_path)
        @aliases = @data['aliases'] || {}
      end

      def resolve(keycode)
        # エイリアスを実際のQMKキーコードに変換
        @aliases[keycode] || keycode
      end

      def reverse_resolve(qmk_keycode)
        # QMKキーコードからエイリアスを検索（定義順で最初にマッチ）
        @aliases.each do |alias_name, qmk_code|
          return alias_name if qmk_code == qmk_keycode
        end
        qmk_keycode  # 見つからない場合は元のキーコードを返す
      end
    end
  end
end
