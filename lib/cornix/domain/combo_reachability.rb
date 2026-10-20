# frozen_string_literal: true

require 'set'
require_relative 'keycode'
require_relative 'keycode/no_key'

module Cornix
  module Domain
    # コンボを押せるか（トリガーのキーがすべてそろうレイヤーがあるか）の判定。
    # ProfileDiagnostics の警告「押せないコンボ」と、エディタの snapshot の combos の reachable が使う。
    #
    #   reachability = ComboReachability.new(profile)
    #   reachability.reachable?(combo)   #=> true / false
    #
    # レイヤーごとに、そのレイヤーで押せるキーコードを集める: 位置の割り当てとエンコーダのプッシュ（マトリクスのキー）。
    # KC_TRNS の位置はレイヤー 0（番号 0 のレイヤー。なければ何もない）の同じ位置の値で見る。割り当てのない位置は KC_NO なので数えない。
    # どれかのレイヤーで、トリガーのキー（KC_NO を除く）がすべて入っていれば押せる。
    # トリガーが KC_NO だけのコンボ（作ったばかりのもの）は押せる扱い（印を付けない）。
    # キーコードは値そのもので比べる（LT(1, KC_A) の位置では KC_A のトリガーはそろわない。QMK のコンボと同じ）
    class ComboReachability
      ENCODER_SIDES = %i[left right].freeze

      def initialize(profile)
        @profile = profile
      end

      def reachable?(combo)
        triggers = combo.trigger_keys.reject { |kc| kc == Keycode::NO_KEY }.uniq
        return true if triggers.empty?

        layer_keycodes.any? { |keycodes| triggers.all? { |kc| keycodes.include?(kc) } }
      end

      private

      # レイヤーごとの押せるキーコードの Set
      def layer_keycodes
        @layer_keycodes ||= begin
          base = @profile.layer(0)
          @profile.layers.map { |layer| keycodes(layer, base) }
        end
      end

      def keycodes(layer, base)
        set = Set.new
        layer.keys.each { |position, kc| add(set, kc) { base&.key(position) } }
        ENCODER_SIDES.each { |side| add(set, layer.encoder(side).push) { base&.encoder(side)&.push } }
        set
      end

      # KC_TRNS はレイヤー 0 の値（ブロックの戻り値）に置き換える。レイヤー 0 でも KC_TRNS なら数えない
      def add(set, keycode)
        keycode = yield if keycode == Keycode::TRANSPARENT
        set << keycode unless keycode.nil? || keycode == Keycode::TRANSPARENT || keycode == Keycode::NO_KEY
      end
    end
  end
end
