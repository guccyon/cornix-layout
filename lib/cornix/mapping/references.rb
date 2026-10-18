# frozen_string_literal: true

module Cornix
  module Mapping
    # Macro('名前') / TapDance('名前') と番号の対応表、Shortcut('名前') と Keycode の対応表。
    # KeycodeNotation が名前参照を読み書きするときに使う。Storage が読み込んだマクロ・
    # タップダンスの名前と shortcuts.yaml、同梱のショートカット（preset_shortcuts）から作る。
    # 名前を持たない場面（.vil、マクロの keys など）では NONE を使う。
    # shortcuts に nil を渡すと（NONE も）Shortcut('名前') を使えない場面になる（shortcuts_available? が false）。
    #
    # Shortcut('名前') を読むときは shortcuts（利用者の定義）を先に引き、なければ preset_shortcuts を引く（同じ名前は利用者の定義が勝つ）。
    # 書くとき（shortcut_name）は shortcuts だけを使う（同梱の定義と同じ値が勝手に Shortcut('アプリ:...') にならないように）
    class References
      def initialize(macros: {}, tap_dances: {}, shortcuts: nil, preset_shortcuts: {})
        @macros = macros.dup.freeze
        @tap_dances = tap_dances.dup.freeze
        @shortcuts_available = !shortcuts.nil?
        @shortcuts = (shortcuts || {}).dup.freeze
        @preset_shortcuts = preset_shortcuts.dup.freeze
        @macro_names = @macros.invert.freeze
        @tap_dance_names = @tap_dances.invert.freeze
        @shortcut_names = @shortcuts.group_by(&:last).transform_values { |pairs| pairs.map(&:first) }.freeze
        freeze
      end

      def macro_index(name) = @macros[name]

      def tap_dance_index(name) = @tap_dances[name]

      def macro_name(index) = @macro_names[index]

      def tap_dance_name(index) = @tap_dance_names[index]

      # Shortcut('名前') を使える場面か
      def shortcuts_available? = @shortcuts_available

      # 名前のショートカットの Keycode（利用者の定義、なければ同梱の定義）。どちらにもなければ nil
      def shortcut(name) = @shortcuts[name] || @preset_shortcuts[name]

      # keycode をちょうど 1 つの利用者のショートカットが定義していればその名前。なし・複数なら nil。
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
