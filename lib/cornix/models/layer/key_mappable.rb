# frozen_string_literal: true

module Cornix
  module Models
    class Layer
      # KeyMappable: KeyMapping と NullKeyMapping の共通インターフェース
      #
      # このモジュールを include することで、以下のメソッドが必須となります：
      # - symbol: position_map上のシンボル名を返す
      # - to_qmk: QMK数値コードに変換
      # - to_yaml: YAML形式の文字列に変換
      # - logical_coord: 論理座標を返す
      module KeyMappable
        # シンボル名を返す（例: 'Q', 'tab'）
        def symbol
          raise NotImplementedError, "#{self.class} must implement #symbol"
        end

        # QMK数値コードに変換
        #
        # @param keycode_converter [KeycodeConverter] キーコード解決器
        # @param reference_converter [ReferenceConverter, nil] 参照解決器
        # @return [String, Integer] QMKキーコード
        def to_qmk(keycode_converter, reference_converter: nil)
          raise NotImplementedError, "#{self.class} must implement #to_qmk"
        end

        # YAML形式の文字列に変換
        #
        # @return [String, nil] YAML値（nilの場合はオーケストレーターでcompact）
        def to_yaml
          raise NotImplementedError, "#{self.class} must implement #to_yaml"
        end

        # 論理座標を返す
        #
        # @return [Hash, nil] { hand: :left/:right, row: 0-3, col: 0-5 } または nil
        def logical_coord
          raise NotImplementedError, "#{self.class} must implement #logical_coord"
        end
      end
    end
  end
end
