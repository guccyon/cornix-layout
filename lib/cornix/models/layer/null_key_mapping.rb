# frozen_string_literal: true

require_relative 'key_mappable'

module Cornix
  module Models
    class Layer
      # NullKeyMapping: Null Object Pattern の実装
      #
      # KeyMapping が存在しない場合のデフォルト値として使用します。
      # nil チェックを不要にし、ポリモーフィックな処理を可能にします。
      #
      # 主な特徴：
      # - symbol → nil
      # - to_qmk → -1 (NoKey)
      # - to_yaml → nil (オーケストレーターで compact される)
      # - logical_coord → nil
      class NullKeyMapping
        include KeyMappable

        # シンボル名（nil）
        def symbol
          nil
        end

        # QMK数値コード（-1 = NoKey）
        #
        # @param keycode_converter [KeycodeConverter] 未使用
        # @param reference_converter [ReferenceConverter, nil] 未使用
        # @return [Integer] -1
        def to_qmk(keycode_converter, reference_converter: nil)
          -1
        end

        # YAML形式の文字列（nil = blank）
        #
        # @return [nil]
        def to_yaml
          nil
        end

        # 論理座標（nil）
        #
        # @return [nil]
        def logical_coord
          nil
        end
      end

      # 定数: NULL_KEY - 不変な NullKeyMapping インスタンス
      #
      # 全ての NullKeyMapping は同じインスタンスを共有します（メモリ効率）。
      # freeze により、不変性を保証します。
      NULL_KEY = NullKeyMapping.new.freeze
    end
  end
end
