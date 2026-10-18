# frozen_string_literal: true

module Cornix
  module Mapping
    # Macro('名前') / TapDance('名前') と番号の対応表。
    # KeycodeNotation が名前参照を読み書きするときに使う。Storage が読み込んだマクロと
    # タップダンスの名前から作る。名前を持たない場面（.vil など）では NONE を使う。
    class References
      def initialize(macros: {}, tap_dances: {})
        @macros = macros.dup.freeze
        @tap_dances = tap_dances.dup.freeze
        @macro_names = @macros.invert.freeze
        @tap_dance_names = @tap_dances.invert.freeze
        freeze
      end

      def macro_index(name) = @macros[name]

      def tap_dance_index(name) = @tap_dances[name]

      def macro_name(index) = @macro_names[index]

      def tap_dance_name(index) = @tap_dance_names[index]

      NONE = new
    end
  end
end
