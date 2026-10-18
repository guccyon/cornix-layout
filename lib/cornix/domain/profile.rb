# frozen_string_literal: true

require_relative 'checks'
require_relative 'metadata'
require_relative 'qmk_settings'
require_relative 'position_map'
require_relative 'layer'
require_relative 'macro'
require_relative 'tap_dance'
require_relative 'combo'
require_relative 'capabilities'

module Cornix
  module Domain
    # 集約ルート。設定ファイル一式（= layout.vil 1 つ）が表すキーボードの状態。
    # layers / macros / tap_dances / combos は渡された順のまま持つ（番号は各要素の index）。
    # 番号や名前の重複、上限、参照先の存在は #diagnostics で検査する
    class Profile < Data.define(:metadata, :settings, :position_map, :layers, :macros, :tap_dances, :combos)
      def initialize(metadata:, settings:, position_map:, layers:, macros: [], tap_dances: [], combos: [])
        super(
          metadata: Checks.instance!(metadata, Metadata, 'メタデータ'),
          settings: Checks.instance!(settings, QmkSettings, 'QMK の設定'),
          position_map: Checks.instance!(position_map, PositionMap, 'position_map'),
          layers: list!(layers, Layer, 'レイヤー'),
          macros: list!(macros, Macro, 'マクロ'),
          tap_dances: list!(tap_dances, TapDance, 'タップダンス'),
          combos: list!(combos, Combo, 'コンボ')
        )
      end

      # 番号の要素。なければ nil（重複していれば先のもの）
      def layer(index) = layers.find { |l| l.index == index }
      def macro(index) = macros.find { |m| m.index == index }
      def tap_dance(index) = tap_dances.find { |t| t.index == index }
      def combo(index) = combos.find { |c| c.index == index }

      # マクロの名前 => 番号（名前が重複していれば先のもの）
      def macro_names = names_of(macros)

      # タップダンスの名前 => 番号（名前が重複していれば先のもの）
      def tap_dance_names = names_of(tap_dances)

      # 名前参照（Macro('名前') / TapDance('名前')）の対応表。
      # Mapping の References.new(**profile.references) にそのまま渡せる形
      def references = { macros: macro_names, tap_dances: tap_dance_names }

      # 意味検証の結果（Diagnostic の一覧）
      def diagnostics(capabilities = Capabilities::CORNIX) = ProfileDiagnostics.new(self, capabilities).call

      private

      def list!(value, klass, what)
        Checks.list!(value, what) { |item, i| Checks.instance!(item, klass, "#{what}[#{i}]") }
      end

      def names_of(items)
        items.each_with_object({}) { |item, h| h[item.name] = item.index unless h.key?(item.name) }.freeze
      end
    end
  end
end

require_relative 'profile_diagnostics'
