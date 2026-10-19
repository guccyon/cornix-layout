# frozen_string_literal: true

require_relative 'snapshot'
require_relative 'candidates'
require_relative 'inspect/description'

module Cornix
  module Application
    module Editor
      # 1 つの表記の解釈（protocol.md の 5.5 keycode/inspect）。入力欄の onchange の検証と、マウスを載せたときの説明に使う。
      #
      #   Inspect.new(workbench).call('p1', context: 'layerKey', text: "Macro('Bracket Pair')")
      #   #=> { value: KeyValue | nil, diagnostics: [Diagnostic（address なし）], description: { title:, lines: } | nil }
      #
      # 参照先は保存済みのプロファイルで判断する（構造検証で読めなければ、マクロ・タップダンスの名前なしで読み、意味検証はしない）。
      # 読めない表記は value と description が nil で、構造の error を 1 件返す。
      # 読めれば Profile#diagnostics と同じ規則（参照先がない・レイヤーの範囲・Cornix が対応していないキー）の問題を返す。
      # 規則を Domain から写さないよう、その値を出力に持つコンボを 1 件足したプロファイルを検証し、その場所の結果だけを取る。
      # 知らない context は Candidates::UnknownContext（v0.1 の context による違いはない）
      class Inspect
        PROBE_NAME = 'keycode/inspect'

        def initialize(workbench, icons: Mapping::AppIconCatalog.default)
          @workbench = workbench
          @icons = icons
        end

        def call(id, context:, text:)
          env = @workbench.fetch(id).env
          raise Candidates::UnknownContext, context unless Mapping::CandidateCatalog.default_categories.context?(context)

          reading = Snapshot::Reading.read(env)
          values = Snapshot::KeyValues.new(env: env, profile: reading.profile, icons: @icons)
          keycode = values.parse(text)
          value = values.build(keycode, text: text)
          { value: value, diagnostics: semantic(reading.profile, keycode, env.capabilities),
            description: Description.new(values: values, profile: reading.profile).call(keycode, value) }
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
