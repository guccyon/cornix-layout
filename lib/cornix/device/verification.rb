# frozen_string_literal: true

module Cornix
  module Device
    # 書き込み後に読み直した DeviceImage で、各 Change の場所が目標（to）になっているかを確かめる
    class Verification
      def initialize(image)
        @image = image
      end

      # 目標と一致しない Change
      def remaining(changes) = changes.reject { |change| applied?(change) }

      def applied?(change)
        case change
        when Planning::Change::SetKeycode then @image.layers.dig(change.layer, change.row, change.col) == change.to
        when Planning::Change::SetEncoder then encoder_value(change) == change.to
        when Planning::Change::SetTapDance then @image.tap_dances[change.index] == change.to
        when Planning::Change::SetCombo then @image.combos[change.index] == change.to
        when Planning::Change::ReplaceMacros then macros_applied?(change)
        when Planning::Change::SetSetting then @image.settings[change.qsid] == change.to
        else false
        end
      end

      private

      def encoder_value(change)
        record = @image.encoders.dig(change.layer, change.index)
        record && (change.clockwise ? record.cw : record.ccw)
      end

      def macros_applied?(change)
        change.to.each_index.all? do |i|
          Planning::MacroList.same?(@image.macros[i] || [], change.to[i])
        end
      end
    end
  end
end
