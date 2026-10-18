# frozen_string_literal: true

module Cornix
  module Storage
    module Schema
      # tap_dance/{番号 2 桁}_{名前}.yaml
      #
      #   name: Tab Escape
      #   description: ...          # 省略可
      #   enabled: true             # 省略可（読み飛ばす）
      #   index: 4                  # タップダンス番号（TD(4)）
      #   actions:                  # 省略した動作は KC_NO。注記付きの形（{ key: ..., note: ... }）も書ける
      #     on_tap: KC_TAB
      #     on_hold: KC_ESCAPE
      #     on_double_tap: KC_NO
      #     on_tap_hold: KC_NO
      #   tapping_term: 200         # ミリ秒。省略すると 250
      #
      # 旧形式（actions: を使わず on_tap などをトップレベルに書く）も読む
      module TapDanceFile
        ACTIONS = Domain::TapDance::ACTIONS.map(&:to_s).freeze
        KEYS = (%w[name description enabled index actions tapping_term] + ACTIONS).freeze
        DEFAULT_TAPPING_TERM = 250

        module_function

        def read(data, ctx, keycodes)
          hash = ctx.mapping(data, '', required: %w[name index], allowed: KEYS) or return nil
          name = ctx.name(hash['name'], 'name')
          description = ctx.description(hash['description'])
          index = ctx.bounded(hash['index'], 'index', Domain::Keycode::TapDanceCall::RANGE, 'タップダンス番号')
          actions = read_actions(hash, ctx, keycodes)
          term = read_tapping_term(hash['tapping_term'], ctx)
          return nil if [name, index, actions, term].any?(&:nil?) || description == :invalid

          ctx.build('') do
            Domain::TapDance.new(index: index, name: name, description: description, tapping_term: term,
                                 **actions.transform_values(&:keycode), notes: KeycodeField.notes(actions))
          end
        end

        def read_actions(hash, ctx, keycodes)
          top_level = ACTIONS.select { |a| hash.key?(a) }
          source, prefix = hash.key?('actions') ? [hash['actions'], 'actions'] : [hash.slice(*ACTIONS), '']
          if hash.key?('actions') && !top_level.empty?
            ctx.problem('', "actions と #{top_level.join(', ')} の両方があります（actions の中に書いてください）")
          end
          return empty_actions if source.nil?

          table = ctx.mapping(source, prefix, allowed: ACTIONS) or return nil
          actions = ACTIONS.to_h do |a|
            no = Domain::Keycode::NO_KEY
            [a.to_sym, keycodes.read_assignment(table[a], ctx, Schema.join(prefix, a), default: no)]
          end
          actions.values.all? ? actions : nil
        end

        def empty_actions
          none = KeycodeField::Assignment.new(keycode: Domain::Keycode::NO_KEY, note: nil)
          ACTIONS.to_h { |a| [a.to_sym, none] }
        end

        def read_tapping_term(raw, ctx)
          return DEFAULT_TAPPING_TERM if raw.nil?

          ctx.bounded(raw, 'tapping_term', Domain::TapDance::TAPPING_TERM_RANGE, 'tapping_term（ミリ秒）')
        end

        # 旧 YamlWriter と同じ形（index, name, description, actions, tapping_term）
        def write(tap_dance, keycodes)
          {
            'index' => tap_dance.index,
            'name' => tap_dance.name,
            'description' => tap_dance.description || '',
            'actions' => tap_dance.actions.to_h { |a, kc| [a.to_s, keycodes.write_assignment(kc, tap_dance.note(a))] },
            'tapping_term' => tap_dance.tapping_term
          }
        end
      end
    end
  end
end
