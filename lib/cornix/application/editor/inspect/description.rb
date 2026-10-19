# frozen_string_literal: true

module Cornix
  module Application
    module Editor
      class Inspect
        # マウスを載せたときの説明（protocol.md の 5.5 の description）。
        #
        #   Description.new(values:, profile:, qmk:).call(keycode, value)   #=> { title:, lines: [...] }（value は KeyValues#build の結果、qmk は QmkName）
        #
        # 出すもの（どれも最後に QMK の名前の行「QMK: LT(1, KC_SPACE)（0x412C）」。QMK の名前にできない値は「16bit 値: 0x7E40」）
        #   Shortcut('名前')   title「ショートカット 名前」、中身の表記（Shift + Command + P）
        #   マクロ             title「マクロ 名前（M0）」、説明・preset の名前・手順（tap: [ ] ← のように 1 手順 1 行）
        #   タップダンス       title「タップダンス 名前（TD(4)）」、説明・4 つの動作（割り当てのあるものだけ）・tapping_term
        #   レイヤー操作       title は正規形、行き先のレイヤー（番号と名前。定義がなければそう書く）。LT はタップ側のキーも
        #   Mod-Tap           title は正規形、タップ側とホールド側
        #   そのほか          title は正規形
        class Description
          K = Domain::Keycode
          TAP_DANCE_ACTIONS = { on_tap: 'タップ', on_hold: 'ホールド', on_double_tap: 'ダブルタップ',
                                on_tap_hold: 'タップのあとホールド' }.freeze

          def initialize(values:, profile:, qmk:)
            @values = values
            @profile = profile
            @qmk = qmk
          end

          def call(keycode, value)
            title, lines = describe(keycode, value)
            { title: title, lines: lines + [code_line(keycode, value[:code])] }
          end

          private

          def code_line(keycode, code)
            hex = format('0x%04X', code)
            (name = @qmk.call(keycode)) ? "QMK: #{name}（#{hex}）" : "16bit 値: #{hex}"
          end

          def describe(keycode, value)
            if (name = @values.shortcut_name(value[:text]))
              kind = @values.user_shortcut?(name) ? 'ショートカット' : '同梱のショートカット'
              return ["#{kind} #{name}", [@values.plain(keycode)]]
            end

            case keycode
            when K::MacroCall then macro(keycode.index)
            when K::TapDanceCall then tap_dance(keycode.index)
            when K::LayerAction, K::LayerMod then [canonical(keycode), [layer_line(keycode.layer.index)]]
            when K::LayerTap
              [canonical(keycode), ["タップ: #{@values.plain(keycode.base)}", "ホールド: #{layer_line(keycode.layer.index)}"]]
            when K::ModTap
              [canonical(keycode), ["タップ: #{@values.plain(keycode.base)}", "ホールド: #{value[:display][:hold]}"]]
            else [canonical(keycode), []]
            end
          end

          def canonical(keycode) = @values.canonical(keycode)

          def macro(index)
            macro = @profile&.macro(index)
            return ["マクロ M#{index}", ['定義されていません']] unless macro

            lines = [macro.description, macro.preset && "同梱のショートカット: #{macro.preset}"].compact.reject(&:empty?)
            ["マクロ #{macro.name}（M#{index}）", lines + macro.steps.map { |step| step_line(step) }]
          end

          def step_line(step)
            case step
            when Domain::MacroStep::Delay then "delay: #{step.ms}ms"
            when Domain::MacroStep::Text then "text: #{step.content}"
            else "#{step.kind}: #{step.keys.map { |kc| @values.label(kc) }.join(' ')}"
            end
          end

          def tap_dance(index)
            tap_dance = @profile&.tap_dance(index)
            return ["タップダンス TD(#{index})", ['定義されていません']] unless tap_dance

            lines = [tap_dance.description].compact.reject(&:empty?)
            lines += TAP_DANCE_ACTIONS.filter_map do |action, label|
              kc = tap_dance.public_send(action)
              "#{label}: #{canonical(kc)}" unless kc.is_a?(K::NoKey)
            end
            lines << "tapping_term: #{tap_dance.tapping_term}ms"
            ["タップダンス #{tap_dance.name}（TD(#{index})）", lines]
          end

          def layer_line(index)
            layer = @profile&.layer(index)
            layer ? "レイヤー #{index}（#{layer.name}）" : "レイヤー #{index}（定義されていません）"
          end
        end
      end
    end
  end
end
