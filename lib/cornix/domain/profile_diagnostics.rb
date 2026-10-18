# frozen_string_literal: true

require_relative 'diagnostic'
require_relative 'keycode'
require_relative 'keycode/layer_action'
require_relative 'keycode/layer_tap'
require_relative 'keycode/layer_mod'
require_relative 'keycode/macro_call'
require_relative 'keycode/tap_dance_call'
require_relative 'keycode/quantum'
require_relative 'encoder_binding'

module Cornix
  module Domain
    # Profile の意味検証。Profile#diagnostics から使う。
    #
    #   レイヤー      枚数の上限、番号の上限・重複（error）、番号の抜け（warning）
    #   マクロ / タップダンス / コンボ   件数の上限、番号の上限・重複、名前の重複（error）
    #   コンボ        トリガーの数の上限（error）
    #   キーコード    すべての割り当て（レイヤーのキーとエンコーダ、マクロのキー、タップダンスの動作、
    #                 コンボのトリガーと出力）について
    #                 M(n) / TD(n) の参照先がない（error）、レイヤー番号がレイヤー数を超える（error）、
    #                 レイヤー数の内だが定義されていないレイヤーを指す（warning）、
    #                 Capabilities#unsupported_keycodes にある特殊キー（warning。書き込みは止めない）
    class ProfileDiagnostics
      LAYER_REF_TYPES = [Keycode::LayerAction, Keycode::LayerTap, Keycode::LayerMod].freeze

      def initialize(profile, capabilities)
        @profile = profile
        @caps = capabilities
      end

      def call
        @result = []
        check_layers
        check_items('macros', profile.macros, caps.macros, 'マクロ')
        check_items('tap_dances', profile.tap_dances, caps.tap_dances, 'タップダンス')
        check_items('combos', profile.combos, caps.combos, 'コンボ')
        check_combo_keys
        keycode_entries.each { |path, keycode| check_keycode(path, keycode) }
        @result.freeze
      end

      private

      attr_reader :profile, :caps

      def error(path, message) = @result << Diagnostic.error(path, message)
      def warning(path, message) = @result << Diagnostic.warning(path, message)

      # --- レイヤー ---

      def check_layers
        layers = profile.layers
        error('layers', "レイヤーは #{caps.layers} 枚までです: #{layers.size} 枚") if layers.size > caps.layers
        check_indexes('layers', layers, caps.layers, 'レイヤー')
        indexes = layers.map(&:index)
        return if indexes.empty?

        missing = (0..indexes.max).to_a - indexes
        warning('layers', "レイヤー #{missing.join(', ')} がありません") unless missing.empty?
      end

      # --- マクロ / タップダンス / コンボ ---

      def check_items(key, items, limit, what)
        error(key, "#{what}は #{limit} 件までです: #{items.size} 件") if items.size > limit
        check_indexes(key, items, limit, what)
        each_duplicate(items, &:name).each do |item, i|
          error("#{key}[#{i}].name", "#{what}の名前が重複しています: #{item.name}")
        end
      end

      def check_indexes(key, items, limit, what)
        items.each_with_index do |item, i|
          next if item.index < limit

          error("#{key}[#{i}].index", "#{what}の番号は 0〜#{limit - 1} です: #{item.index}")
        end
        each_duplicate(items, &:index).each do |item, i|
          error("#{key}[#{i}].index", "#{what}の番号が重複しています: #{item.index}")
        end
      end

      def check_combo_keys
        profile.combos.each_with_index do |combo, i|
          next if combo.trigger_keys.size <= caps.combo_keys

          error("combos[#{i}].trigger_keys",
                "コンボのトリガーは #{caps.combo_keys} 個までです: #{combo.trigger_keys.size} 個")
        end
      end

      # 値が前に出てきた要素（2 件目以降）を [要素, 位置] で返す
      def each_duplicate(items)
        seen = {}
        items.each_with_index.filter_map do |item, i|
          value = yield item
          dup = seen.key?(value)
          seen[value] = true
          [item, i] if dup
        end
      end

      # --- キーコード ---

      def check_keycode(path, keycode)
        case keycode
        when Keycode::MacroCall
          error(path, "マクロ M#{keycode.index} が定義されていません") unless macro_indexes.include?(keycode.index)
        when Keycode::TapDanceCall
          error(path, "タップダンス TD(#{keycode.index}) が定義されていません") unless tap_dance_indexes.include?(keycode.index)
        when *LAYER_REF_TYPES
          check_layer_ref(path, keycode.layer.index)
        when Keycode::Quantum
          check_supported(path, keycode.code)
        end
      end

      def check_supported(path, code)
        message = caps.unsupported_keycodes[code]
        warning(path, "#{message}（書き込みますが、押しても動かない可能性があります）") if message
      end

      def check_layer_ref(path, index)
        if index >= caps.layers
          error(path, "レイヤー #{index} はありません（レイヤーは 0〜#{caps.layers - 1}）")
        elsif !layer_indexes.include?(index)
          warning(path, "レイヤー #{index} が定義されていません")
        end
      end

      def macro_indexes = @macro_indexes ||= profile.macros.map(&:index)
      def tap_dance_indexes = @tap_dance_indexes ||= profile.tap_dances.map(&:index)
      def layer_indexes = @layer_indexes ||= profile.layers.map(&:index)

      # [パス, Keycode] の一覧
      def keycode_entries
        layer_entries + macro_entries + tap_dance_entries + combo_entries
      end

      def layer_entries
        order = profile.position_map.positions.each_with_index.to_h
        profile.layers.each_with_index.flat_map do |layer, i|
          keys = layer.keys.sort_by { |pos, _| order.fetch(pos) }
                      .map { |pos, kc| ["layers[#{i}].#{profile.position_map.path(pos)}", kc] }
          encoders = layer.encoders.sort_by { |side, _| side == :left ? 0 : 1 }.flat_map do |side, binding|
            binding.actions.map { |a, kc| ["layers[#{i}].encoders.#{side}.#{a}", kc] }
          end
          keys + encoders
        end
      end

      def macro_entries
        profile.macros.each_with_index.flat_map do |macro, i|
          macro.steps.each_with_index.flat_map do |step, j|
            next [] unless step.respond_to?(:keys)

            step.keys.each_with_index.map { |kc, k| ["macros[#{i}].steps[#{j}].keys[#{k}]", kc] }
          end
        end
      end

      def tap_dance_entries
        profile.tap_dances.each_with_index.flat_map do |td, i|
          td.actions.map { |action, kc| ["tap_dances[#{i}].#{action}", kc] }
        end
      end

      def combo_entries
        profile.combos.each_with_index.flat_map do |combo, i|
          triggers = combo.trigger_keys.each_with_index.map { |kc, k| ["combos[#{i}].trigger_keys[#{k}]", kc] }
          triggers + [["combos[#{i}].output_key", combo.output_key]]
        end
      end
    end
  end
end
