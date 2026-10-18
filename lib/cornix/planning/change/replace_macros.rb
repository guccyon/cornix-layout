# frozen_string_literal: true

module Cornix
  module Planning
    module Change
      # マクロ領域全体の書き直し（Vial のマクロは領域全体を先頭から書く）。
      # from / to は全マクロ（[[Image::MacroAction]]、デバイスのマクロ数ぶん）、indexes は中身が変わるマクロの番号
      class ReplaceMacros < Data.define(:indexes, :from, :to)
        include Value

        KEY_KINDS = %i[tap down up].freeze

        # 変わるマクロに含まれるキーコード
        def keycodes
          to.values_at(*indexes).flatten(1).flat_map { |action| KEY_KINDS.include?(action.kind) ? action.keys : [] }
        end
      end
    end
  end
end
