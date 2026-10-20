# frozen_string_literal: true

require_relative 'profile_reading'
require_relative 'key_values'
require_relative 'unknown_context'
require_relative 'inspect/description'

module Cornix
  module Application
    module Editor
      # 1 つの表記の解釈（protocol.md の 5.5 keycode/inspect）。入力欄の onchange の検証と、マウスを載せたときの説明に使う。
      #
      #   Inspect.new(workbench).call('p1', context: 'layerKey', text: "Macro('Bracket Pair')")
      #   #=> { value: KeyValue | nil, diagnostics: [Diagnostic（address なし）], description: { title:, lines: } | nil }
      #
      # 参照先は保存済みのプロファイルで判断する（構造検証で読めなければ、キーの表と同梱のショートカットだけで読み、意味検証はしない）。
      # 読めない表記は value と description が nil で、構造の error を 1 件返す。
      # 読めれば Profile#diagnostics と同じ規則（参照先がない・レイヤーの範囲・Cornix が対応していないキー）の問題を返す。
      # 規則を Domain から写さないよう、その値を出力に持つコンボを 1 件足したプロファイルを検証し、その場所の結果だけを取る。
      # これは今の規則（ProfileDiagnostics#check_keycode）がキーコードの場所によらないことに頼っている。Domain に 1 つのキーコードだけを
      # 確かめる公開メソッド（Profile#keycode_diagnostics など）ができたら置き換える（spec でレイヤーのキーに置いたときの結果と比べている）。
      # 知らない context は UnknownContext。context による違いは読める名前参照だけ（KeyValues の context。
      # macroKey は名前参照を読まず、shortcutValue は Shortcut(...) を読まない。読み込みと同じ文の構造の error になる）
      class Inspect
        PROBE_NAME = 'keycode/inspect'

        def initialize(workbench, icons: Mapping::AppIconCatalog.default)
          @workbench = workbench
          @icons = icons
        end

        def call(id, context:, text:)
          env = @workbench.fetch(id).env
          UnknownContext.check!(context)
          reading = ProfileReading.read(env)
          values = KeyValues.new(env: env, profile: reading.profile, icons: @icons)
          keycode = values.parse(text, context: context)
          value = values.build(keycode, text: text, context: context)
          { value: value, diagnostics: semantic(reading.profile, keycode, env.capabilities),
            description: Description.new(values: values, profile: reading.profile, qmk: env.qmk).call(keycode, value) }
        rescue UnknownKeycode => e
          { value: nil, diagnostics: [{ severity: 'error', message: e.message, source: 'structure' }], description: nil }
        end

        private

        def semantic(profile, keycode, capabilities)
          return [] unless profile

          position = profile.combos.size
          probe = Domain::Combo.new(index: Domain::Combo::INDEX_RANGE.max, name: PROBE_NAME, trigger_keys: [Domain::Keycode::NO_KEY],
                                    output_key: keycode)
          path = "combos[#{position}].output_key"
          profile.with(combos: profile.combos + [probe]).diagnostics(capabilities)
                 .select { |d| d.path == path }
                 .map { |d| { severity: d.severity.to_s, message: d.message, source: 'semantic' } }
        end
      end
    end
  end
end
