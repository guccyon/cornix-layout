# frozen_string_literal: true

require_relative 'checks'
require_relative 'metadata'
require_relative 'qmk_settings'
require_relative 'position_map'
require_relative 'layer'
require_relative 'macro'
require_relative 'tap_dance'
require_relative 'combo'
require_relative 'shortcut_library'
require_relative 'capabilities'
require_relative 'keycode/layer_action'
require_relative 'keycode/layer_tap'
require_relative 'keycode/layer_mod'

module Cornix
  module Domain
    # 集約ルート。設定ファイル一式（= layout.vil 1 つ）が表すキーボードの状態。
    # layers / macros / tap_dances / combos は渡された順のまま持つ（番号は各要素の index）。
    # shortcuts は名前付きショートカット（Shortcut('名前') の参照先。設定ファイルにだけあり、デバイスには書かない）。
    # 番号や名前の重複、上限、参照先の存在は #diagnostics で検査する
    class Profile < Data.define(:metadata, :settings, :position_map, :layers, :macros, :tap_dances, :combos, :shortcuts)
      LAYER_REF_TYPES = [Keycode::LayerAction, Keycode::LayerTap, Keycode::LayerMod].freeze

      def initialize(metadata:, settings:, position_map:, layers:, macros: [], tap_dances: [], combos: [],
                     shortcuts: ShortcutLibrary::EMPTY)
        super(
          metadata: Checks.instance!(metadata, Metadata, 'メタデータ'),
          settings: Checks.instance!(settings, QmkSettings, 'QMK の設定'),
          position_map: Checks.instance!(position_map, PositionMap, 'position_map'),
          layers: list!(layers, Layer, 'レイヤー'),
          macros: list!(macros, Macro, 'マクロ'),
          tap_dances: list!(tap_dances, TapDance, 'タップダンス'),
          combos: list!(combos, Combo, 'コンボ'),
          shortcuts: Checks.instance!(shortcuts, ShortcutLibrary, 'ショートカット')
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

      # 名前参照（Macro('名前') / TapDance('名前') / Shortcut('名前')）の対応表。
      # Mapping の References.new(**profile.references) にそのまま渡せる形
      def references = { macros: macro_names, tap_dances: tap_dance_names, shortcuts: shortcuts.entries }

      # レイヤー操作のキー（MO(n) / TG(n) / TO(n) / LT(n, kc) / LM(n, mod) など）が指すレイヤーの番号の一覧（昇順・重複なし）。
      # レイヤーのキーとエンコーダ、マクロのキー、タップダンスの動作、コンボのトリガーと出力から集める
      def referenced_layer_indexes
        all_keycodes.filter_map { |kc| kc.layer.index if LAYER_REF_TYPES.any? { |t| kc.is_a?(t) } }.uniq.sort
      end

      # 意味検証の結果（Diagnostic の一覧）
      def diagnostics(capabilities = Capabilities::CORNIX) = ProfileDiagnostics.new(self, capabilities).call

      private

      def all_keycodes
        layer_keycodes = layers.flat_map do |layer|
          layer.keys.values + layer.encoders.values.flat_map { |binding| binding.actions.values }
        end
        macro_keycodes = macros.flat_map { |m| m.steps.flat_map { |s| s.respond_to?(:keys) ? s.keys : [] } }
        layer_keycodes + macro_keycodes + tap_dances.flat_map { |td| td.actions.values } +
          combos.flat_map { |c| c.trigger_keys + [c.output_key] }
      end

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
