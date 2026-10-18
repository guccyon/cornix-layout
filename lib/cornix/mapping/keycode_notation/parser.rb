# frozen_string_literal: true

require_relative '../keycode_notation'
require_relative 'modifiers'

module Cornix
  module Mapping
    class KeycodeNotation
      # 設定ファイルのキーコード文字列 → Domain::Keycode（受け付ける表記は KeycodeNotation を参照）。
      #
      # 解釈の順序
      #   1. 文字列全体が別名・QMK 名（"+", "(", "LCtrl" のように記号や修飾名と同じ別名を先に拾う）
      #   2. 参照 Macro(...) / TapDance(...) / Shortcut('名前') / Combo(...)
      #   3. 旧形式のマクロ M3
      #   4. 生の値 0xHHHH
      #   5. 修飾キー式（"修飾名 +" で始まる）
      #   6. 関数形式 NAME(引数, ...)
      class Parser
        K = Domain::Keycode

        # 解析の途中で失敗した理由。parse の入口で文字列全体を添えた UnknownKeycode にする
        class Failure < StandardError; end
        private_constant :Failure

        LAYER_OPS = {
          'TO' => :to, 'MO' => :momentary, 'DF' => :default, 'TG' => :toggle,
          'OSL' => :one_shot, 'TT' => :tap_toggle, 'PDF' => :persistent_default
        }.freeze

        REFERENCE = /\A(Macro|TapDance|Shortcut|Combo)\s*\((.*)\)\z/m
        LEGACY_MACRO = /\AM(\d+)\z/
        HEX = /\A0[xX](\h{1,4})\z/
        FUNCTION = /\A([A-Za-z_][A-Za-z0-9_]*)\s*\((.*)\)\z/m
        MODIFIER_HEAD = /\A([A-Za-z][A-Za-z0-9_]*)\s*\+\s*/
        QUOTED = /\A(['"])(.+)\1\z/m
        INTEGER = /\A\d+\z/

        def initialize(catalog:, codec:)
          @catalog = catalog
          @codec = codec
        end

        def parse(input, references)
          case input
          when Integer then return integer_value(input)
          when String then text = input.strip
          else raise UnknownKeycode, "キーコードは文字列で書いてください: #{input.inspect}"
          end
          raise UnknownKeycode, 'キーコードが空です' if text.empty?

          term(text, references)
        rescue Failure, InvalidValue => e
          raise UnknownKeycode, "キーコード「#{input}」を解釈できません: #{e.message}"
        end

        private

        # YAML に数値で書かれた値は 16bit のキーコードそのもの（旧 KeycodeConverter と同じ）
        def integer_value(value)
          raise UnknownKeycode, "キーコードの値は 0〜0xFFFF です: #{value}" unless value.between?(0, 0xFFFF)

          @codec.decode(value)
        end

        def term(text, refs)
          text = text.strip
          fail!('キーがありません') if text.empty?

          if (code = @catalog.lookup(text)) then @codec.decode(code)
          elsif (m = REFERENCE.match(text)) then reference(m[1], m[2].strip, refs)
          elsif (m = LEGACY_MACRO.match(text)) then K::MacroCall.new(index: m[1].to_i)
          elsif (m = HEX.match(text)) then @codec.decode(m[1].to_i(16))
          elsif MODIFIER_HEAD.match?(text) then modifier_expression(text, refs)
          elsif (m = FUNCTION.match(text)) then function(m[1], split_args(m[2]), refs)
          else unknown!(text)
          end
        end

        # --- 参照 ---

        def reference(function, arg, refs)
          fail!("#{function}(...) はキーに割り当てられません（.vil で表せません）") if function == 'Combo'

          if (m = QUOTED.match(arg))
            name = m[1] == "'" ? m[2].gsub("\\'", "'") : m[2]
            reference_by_name(function, name, refs)
          elsif function == 'Shortcut'
            fail!("Shortcut(...) の引数は '名前' です: #{arg}")
          elsif INTEGER.match?(arg)
            reference_class(function).new(index: arg.to_i)
          else
            fail!("#{function}(...) の引数は '名前' か番号です: #{arg}")
          end
        end

        def reference_by_name(function, name, refs)
          return shortcut(name, refs) if function == 'Shortcut'

          if function == 'Macro'
            index = refs.macro_index(name) or fail!("マクロ「#{name}」が見つかりません")
          else
            index = refs.tap_dance_index(name) or fail!("タップダンス「#{name}」が見つかりません")
          end
          reference_class(function).new(index: index)
        end

        # Shortcut('名前') は shortcuts.yaml（なければ同梱の data/shortcuts/）の定義の Keycode そのもの
        def shortcut(name, refs)
          refs.shortcut(name.strip) or
            fail!("ショートカット「#{name}」は shortcuts.yaml にも同梱のショートカット（data/shortcuts/）にも定義されていません")
        end

        def reference_class(function) = function == 'Macro' ? K::MacroCall : K::TapDanceCall

        # --- 修飾キー式 ---

        def modifier_expression(text, refs)
          pairs = []
          rest = text
          while (m = MODIFIER_HEAD.match(rest))
            pair = Modifiers::EXPRESSION[m[1]]
            unless pair
              fail!("修飾キー名「#{m[1]}」は使えません（使える名前: #{Modifiers::EXPRESSION.keys.join(', ')}）")
            end

            pairs << pair
            rest = m.post_match
          end
          modify(expression_set(pairs), key_term(rest, refs))
        end

        def expression_set(pairs)
          sides = pairs.map(&:first).uniq
          fail!('左右の修飾キーは混在できません（例: Shift と RCmd）') if sides.size > 1

          Domain::ModifierSet.new(side: sides.first, mods: pairs.map(&:last).uniq)
        end

        # 修飾キー式のキーと関数の引数は引用符で囲んでもよい（"Cmd + ]" と "Cmd + ']'"、LT1(',') など）
        def key_term(rest, refs)
          rest = rest.strip
          if @catalog.lookup(rest).nil? && (m = QUOTED.match(rest))
            rest = m[2]
          end
          term(rest, refs)
        end

        # --- 関数形式 ---

        def function(name, args, refs)
          if (bits = Modifiers::FUNCTION_BITS[name])
            arity!(name, args, 1)
            modify(mods(bits), key_term(args[0], refs))
          elsif (bits = Modifiers::MOD_TAP_BITS[name])
            arity!(name, args, 1)
            mod_tap(mods(bits), key_term(args[0], refs))
          elsif name == 'MT'
            arity!(name, args, 2)
            mod_tap(mod_constants(args[0]), key_term(args[1], refs))
          elsif (m = /\ALT(\d+)\z/.match(name))
            arity!(name, args, 1)
            layer_tap(m[1].to_i, key_term(args[0], refs))
          elsif name == 'LT'
            arity!(name, args, 2)
            layer_tap(integer!(name, args[0]), key_term(args[1], refs))
          elsif (op = LAYER_OPS[name])
            arity!(name, args, 1)
            K::LayerAction.new(op: op, layer: layer(integer!(name, args[0])))
          elsif name == 'LM'
            arity!(name, args, 2)
            K::LayerMod.new(layer: layer(integer!(name, args[0])), mods: mod_constants(args[1]))
          elsif name == 'OSM'
            arity!(name, args, 1)
            K::OneShotMod.new(mods: mod_constants(args[0]))
          elsif name == 'TD'
            arity!(name, args, 1)
            K::TapDanceCall.new(index: integer!(name, args[0]))
          else
            fail!("関数 #{name}(...) は使えません")
          end
        end

        # 修飾キー + キー。キーが修飾付きなら修飾キーを足す（Command + Plus → Shift + Command + =）
        def modify(set, key)
          case key
          when K::Basic then K::Modified.new(mods: set, base: key)
          when K::Modified then K::Modified.new(mods: merge(set, key.mods), base: key.base)
          when K::NoKey, K::Transparent then @codec.decode((set.bits << 8) | @codec.encode(key))
          else fail!("修飾キーと組み合わせられるのは基本キーだけです: #{describe(key)}")
          end
        end

        def mod_tap(set, key)
          case key
          when K::Basic then K::ModTap.new(mods: set, base: key)
          when K::NoKey, K::Transparent then @codec.decode(KeycodeCodec::MOD_TAP.begin | (set.bits << 8) | @codec.encode(key))
          else fail!("タップのキーは基本キーだけです: #{describe(key)}")
          end
        end

        def layer_tap(index, key)
          fail!("LT のレイヤー番号は 0〜15 です: #{index}") unless index.between?(0, 15)

          case key
          when K::Basic then K::LayerTap.new(layer: layer(index), base: key)
          when K::NoKey, K::Transparent then @codec.decode(KeycodeCodec::LAYER_TAP.begin | (index << 8) | @codec.encode(key))
          else fail!("タップのキーは基本キーだけです: #{describe(key)}")
          end
        end

        def merge(set, other)
          fail!('左右の修飾キーは混在できません') unless set.side == other.side

          set.merge(other)
        end

        def mods(bits) = Domain::ModifierSet.from_bits(bits)

        def layer(index) = Domain::LayerRef.new(index: index)

        # "MOD_LCTL|MOD_LSFT" → ModifierSet（数値も可）
        def mod_constants(arg)
          parts = arg.split('|').map(&:strip)
          bits = parts.map do |part|
            Modifiers::CONSTANTS[part] || (INTEGER.match?(part) && part.to_i) ||
              fail!("修飾キーの指定 #{part} は不明です（MOD_LCTL|MOD_LSFT のように書きます）")
          end
          sides = bits.map { |b| b.anybits?(Domain::ModifierSet::RIGHT_BIT) }.uniq
          fail!("左右の修飾キーは混在できません: #{arg}") if sides.size > 1

          total = bits.reduce(0, :|)
          fail!("修飾キーの指定が不正です: #{arg}") unless total.between?(0x01, 0x1F) && total.anybits?(0x0F)

          mods(total)
        end

        def integer!(name, arg)
          return arg.to_i if INTEGER.match?(arg.to_s.strip)

          fail!("#{name}(...) の引数は数値です: #{arg}")
        end

        def arity!(name, args, count)
          fail!("#{name}(...) の引数は #{count} 個です") unless args.size == count
        end

        # 括弧と引用符の外側のカンマで区切る
        def split_args(text)
          args = []
          current = +''
          depth = 0
          quote = nil
          text.each_char do |ch|
            if quote
              quote = nil if ch == quote
            elsif ch == "'" || ch == '"'
              quote = ch
            elsif ch == '('
              depth += 1
            elsif ch == ')'
              depth -= 1
            elsif ch == ',' && depth.zero?
              args << current.strip
              current = +''
              next
            end
            current << ch
          end
          args << current.strip
          args == [''] ? [] : args
        end

        def describe(key) = key.class.name.split('::').last

        def unknown!(text)
          hint = suggestion(text)
          fail!("「#{text}」は不明なキーコードです#{"（もしかして: #{hint}）" if hint}")
        end

        # 大文字小文字だけが違う名前を探す
        def suggestion(text)
          @names_by_downcase ||= @catalog.names.group_by(&:downcase)
          @names_by_downcase[text.downcase]&.first
        end

        def fail!(message)
          raise Failure, message
        end
      end
    end
  end
end
