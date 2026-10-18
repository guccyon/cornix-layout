# frozen_string_literal: true

module Cornix
  module Mapping
    class ProfileMapper
      # to_profile で previous（設定ファイルから読んだ Profile）から引き継ぐもの。
      #
      # - レイヤー・マクロ・タップダンス・コンボ: 同じ番号のものの名前と説明。
      #   なければ旧 decompile と同じ名前（"Layer 0" / "Macro 2" / "TapDance 4" / "Combo 1"）で、説明は nil
      # - 注記: 同じ番号のものの同じ場所（キーの位置・エンコーダの操作・タップダンスの動作・コンボの出力）の注記。
      #   キーコードが変わっていない場所だけ引き継ぐ（注記はデバイスにないので、値が変われば意味も変わったとみなす）
      # - メタデータ: keyboard と extra（extra_keys 以外。file_naming / references など）
      class Inheritance
        DEFAULT_NAMES = { layer: 'Layer', macro: 'Macro', tap_dance: 'TapDance', combo: 'Combo' }.freeze

        def initialize(previous)
          @previous = previous
        end

        # kind は :layer / :macro / :tap_dance / :combo
        def name(kind, index) = item(kind, index)&.name || "#{DEFAULT_NAMES.fetch(kind)} #{index}"

        def description(kind, index) = item(kind, index)&.description

        # previous の同じ番号のもの（kind は :layer / :tap_dance / :combo）の注記のうち、
        # 場所のキーコードが current（場所 => Keycode）と同じもの
        def notes(kind, index, current) = same_keycode_notes(item(kind, index), current)

        # previous の同じ番号のレイヤーの side（:left / :right）のエンコーダの注記のうち、キーコードが同じもの
        def encoder_notes(index, side, current) = same_keycode_notes(item(:layer, index)&.encoder(side), current)

        def keyboard = @previous&.metadata&.keyboard || DEFAULT_KEYBOARD

        # previous の metadata の extra（順序を保つ。なければ空）
        def metadata_extra = @previous ? @previous.metadata.extra : {}

        private

        def same_keycode_notes(previous_item, current)
          return {} if previous_item.nil?

          previous_item.notes.select { |slot, _| current.key?(slot) && current[slot] == previous_item.keycode_at(slot) }
        end

        def item(kind, index)
          return nil if @previous.nil?

          @previous.public_send(kind, index)
        end
      end
    end
  end
end
