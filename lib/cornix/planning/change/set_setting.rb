# frozen_string_literal: true

module Cornix
  module Planning
    module Change
      # QMK Settings の 1 項目（qsid は Vial の設定 ID）
      class SetSetting < Data.define(:qsid, :from, :to)
        include Value
      end
    end
  end
end
