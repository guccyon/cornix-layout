# frozen_string_literal: true

require 'did_you_mean'

module Cornix
  module Storage
    module Schema
      # macros/{番号 2 桁}_{名前}.yaml
      #
      #   name: Copy Selected
      #   description: ...          # 省略可
      #   enabled: true             # 省略可（読み飛ばす）
      #   index: 2                  # マクロ番号（M2）
      #   sequence:
      #     - action: down          # tap / down / up は keys（キーコード 1 つ、またはリスト）
      #       keys: KC_LGUI
      #     - action: tap
      #       keys: [KC_C]
      #     - action: delay         # delay は duration（ミリ秒）
      #       duration: 100
      #     - action: text          # text は content（ASCII の文字列）
      #       content: "``````"
      #
      # sequence の代わりに preset（同梱のショートカットの名前）を書くと、その手順のマクロになる（name は省略すると preset の名前）。
      # preset は同梱の定義だけを引く（shortcuts.yaml で同じ名前を上書きしても効かない）:
      #
      #   index: 5
      #   preset: 'macOS:システム:ウィンドウキャプチャ'
      module MacroFile
        KEYS = %w[name description enabled index sequence preset].freeze
        CANDIDATES = 3

        # preset: の名前 → 手順（Mapping::ShortcutCatalog#preset）。NONE は preset: を使えない（どの名前もない）
        Presets = Data.define(:catalog, :notation) do
          def steps(name) = catalog&.preset(name, notation)
          def names = catalog ? catalog.preset_names : []
        end
        Presets.const_set(:NONE, Presets.new(catalog: nil, notation: nil))
        STEP_KEYS = %w[action keys duration content].freeze
        KEY_ACTIONS = Domain::MacroStep::KEY_ACTIONS
        ACTIONS = (KEY_ACTIONS.keys + %w[delay text]).freeze

        module_function

        def read(data, ctx, keycodes, presets = Presets::NONE)
          hash = ctx.mapping(data, '', required: required_keys(data), allowed: KEYS) or return nil
          preset = read_preset(hash, ctx)
          name = hash.key?('name') ? ctx.name(hash['name'], 'name') : Header.name_of(hash, preset: preset.is_a?(String))
          description = ctx.description(hash['description'])
          index = ctx.bounded(hash['index'], 'index', Domain::Keycode::MacroCall::RANGE, 'マクロ番号')
          steps = preset ? preset_steps(preset, ctx, presets) : read_sequence(hash['sequence'], ctx, keycodes)
          return nil if [name, index, steps].any?(&:nil?) || preset == :invalid || description == :invalid

          ctx.build('') do
            Domain::Macro.new(index: index, name: name, description: description, steps: steps, preset: preset)
          end
        end

        # 必ず書くキー。preset を書いたときは name（省くと preset の名前）と sequence はいらない
        def required_keys(data)
          data.is_a?(Hash) && data.key?('preset') ? %w[index] : %w[name index sequence]
        end

        # preset の名前。sequence と preset はどちらか一方。なければ nil、誤りは問題を記録して :invalid
        def read_preset(hash, ctx)
          if hash.key?('preset') && hash.key?('sequence')
            ctx.problem('', 'sequence と preset はどちらか一方だけを書いてください')
            return :invalid
          end
          return nil unless hash.key?('preset')

          ctx.name(hash['preset'], 'preset', 'プリセットの名前（文字列）')&.strip || :invalid
        end

        def preset_steps(name, ctx, presets)
          return nil if name == :invalid

          presets.steps(name) or ctx.problem('preset', unknown_preset(name, presets))
        end

        def unknown_preset(name, presets)
          message = "プリセット「#{name}」は同梱のショートカット（data/shortcuts/）にありません"
          candidates = DidYouMean::SpellChecker.new(dictionary: presets.names).correct(name).first(CANDIDATES)
          candidates.empty? ? message : "#{message}（候補: #{candidates.join(' / ')}）"
        end

        def read_sequence(raw, ctx, keycodes)
          list = ctx.list(raw, 'sequence', '命令のリスト') or return nil
          return ctx.problem('sequence', '命令が 1 つもありません') if list.empty?

          steps = list.each_with_index.map { |item, i| read_step(item, ctx, keycodes, "sequence[#{i}]") }
          steps.all? ? steps : nil
        end

        def read_step(raw, ctx, keycodes, loc)
          hash = ctx.mapping(raw, loc, required: ['action'], allowed: STEP_KEYS) or return nil
          action = ctx.string(hash['action'], "#{loc}.action", "action（#{ACTIONS.join(' / ')}）") or return nil

          case action
          when *KEY_ACTIONS.keys then read_keys(KEY_ACTIONS[action], hash, ctx, keycodes, loc)
          when 'delay' then read_delay(hash, ctx, loc)
          when 'text' then read_text(hash, ctx, loc)
          when 'beep' then ctx.problem("#{loc}.action", 'beep は対応していません')
          else ctx.problem("#{loc}.action", "未知の action です: #{action}（使える action: #{ACTIONS.join(' / ')}）")
          end
        end

        # keys はキーコード 1 つ（文字列）でもリストでもよい（旧 MacroStep.from_yaml_hash と同じ）
        def read_keys(klass, hash, ctx, keycodes, loc)
          raw = hash['keys']
          return ctx.problem(loc, 'keys がありません') if raw.nil?
          return read_key_list(klass, [raw], ctx, keycodes, "#{loc}.keys", single: true) unless raw.is_a?(Array)

          read_key_list(klass, raw, ctx, keycodes, "#{loc}.keys")
        end

        def read_key_list(klass, list, ctx, keycodes, loc, single: false)
          return ctx.problem(loc, 'keys が空です') if list.empty?

          keys = list.each_with_index.map { |v, i| keycodes.read(v, ctx, single ? loc : "#{loc}[#{i}]") }
          return nil unless keys.all?

          ctx.build(loc) { klass.new(keys: keys) }
        end

        def read_delay(hash, ctx, loc)
          return ctx.problem(loc, 'duration がありません') unless hash.key?('duration')

          ms = ctx.integer(hash['duration'], "#{loc}.duration", '待ち時間（ミリ秒の整数）') or return nil
          ctx.build("#{loc}.duration") { Domain::MacroStep::Delay.new(ms: ms) }
        end

        def read_text(hash, ctx, loc)
          return ctx.problem(loc, 'content がありません') unless hash.key?('content')

          text = ctx.string(hash['content'], "#{loc}.content", '入力する文字列') or return nil
          ctx.build("#{loc}.content") { Domain::MacroStep::Text.new(content: text) }
        end

        # 旧 YamlWriter と同じ形（index, name, description, sequence）。keys は常にリスト。
        # プリセットのマクロは sequence の代わりに preset を書く
        def write(macro, keycodes)
          head = { 'index' => macro.index, 'name' => macro.name, 'description' => macro.description || '' }
          return head.merge('preset' => macro.preset) if macro.preset

          head.merge('sequence' => macro.steps.map { |step| write_step(step, keycodes) })
        end

        def write_step(step, keycodes)
          case step
          when Domain::MacroStep::Delay then { 'action' => 'delay', 'duration' => step.ms }
          when Domain::MacroStep::Text then { 'action' => 'text', 'content' => step.content }
          else { 'action' => step.kind.to_s, 'keys' => step.keys.map { |k| keycodes.write(k) } }
          end
        end
      end
    end
  end
end
