# frozen_string_literal: true

module Cornix
  module Mapping
    # Macro('名前') / TapDance('名前') と番号の対応表、Shortcut('名前') と Keycode の対応表。
    # KeycodeNotation が名前参照を読み書きするときに使う。Storage が読み込んだマクロ・
    # タップダンスの名前と shortcuts.yaml から作る。名前を持たない場面（.vil など）では NONE を使う。
    class References
      def initialize(macros: {}, tap_dances: {}, shortcuts: {})
        @macros = macros.dup.freeze
        @tap_dances = tap_dances.dup.freeze
        @shortcuts = shortcuts.dup.freeze
        @macro_names = @macros.invert.freeze
        @tap_dance_names = @tap_dances.invert.freeze
        @shortcut_names = @shortcuts.group_by(&:last).transform_values { |pairs| pairs.map(&:first) }.freeze
        freeze
      end

      def macro_index(name) = @macros[name]

      def tap_dance_index(name) = @tap_dances[name]

      def macro_name(index) = @macro_names[index]

      def tap_dance_name(index) = @tap_dance_names[index]

      # 名前のショートカットの Keycode。なければ nil
      def shortcut(name) = @shortcuts[name]

      # keycode をちょうど 1 つのショートカットが定義していればその名前。なし・複数なら nil。
      # NoKey / Trans は名前で書かない（空き・透過の位置がすべて Shortcut('名前') にならないように）
      def shortcut_name(keycode)
        return nil if keycode.is_a?(Domain::Keycode::NoKey) || keycode.is_a?(Domain::Keycode::Transparent)

        names = @shortcut_names[keycode]
        names&.size == 1 ? names.first : nil
      end

      NONE = new
    end
  end
end
