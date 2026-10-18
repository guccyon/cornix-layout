# frozen_string_literal: true

module Cornix
  module Mapping
    class ProfileMapper
      # to_profile で previous（設定ファイルから読んだ Profile）から引き継ぐもの。
      #
      # - レイヤー・マクロ・タップダンス・コンボ: 同じ番号のものの名前と説明。
      #   なければ旧 decompile と同じ名前（"Layer 0" / "Macro 2" / "TapDance 4" / "Combo 1"）で、説明は nil
      # - メタデータ: keyboard と extra（extra_keys 以外。file_naming / references など）
      class Inheritance
        DEFAULT_NAMES = { layer: 'Layer', macro: 'Macro', tap_dance: 'TapDance', combo: 'Combo' }.freeze

        def initialize(previous)
          @previous = previous
        end

        # kind は :layer / :macro / :tap_dance / :combo
        def name(kind, index) = item(kind, index)&.name || "#{DEFAULT_NAMES.fetch(kind)} #{index}"

        def description(kind, index) = item(kind, index)&.description

        def keyboard = @previous&.metadata&.keyboard || DEFAULT_KEYBOARD

        # previous の metadata の extra（順序を保つ。なければ空）
        def metadata_extra = @previous ? @previous.metadata.extra : {}

        private

        def item(kind, index)
          return nil if @previous.nil?

          @previous.public_send(kind, index)
        end
      end
    end
  end
end
