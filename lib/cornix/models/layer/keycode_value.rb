# frozen_string_literal: true

require_relative '../../keycode_parser'
require_relative '../../modifier_expression_compiler'

module Cornix
  module Models
    class Layer
      # KeycodeValue: キーコード値の基底クラス（ポリモーフィズム）
      #
      # 3種類のキーコードをポリモーフィックに扱う：
      # - PlainKeycode: 単純なキーコード（'Tab', 'Space', 'KC_Q'）
      # - ReferenceKeycode: 参照形式（'Macro("name")', 'TapDance(2)', 'M3'）
      # - FunctionKeycode: 関数形式（'MO(1)', 'LSFT(A)', 'LT(2, Space)'）
      class KeycodeValue
        attr_reader :raw_value

        def initialize(raw_value:)
          @raw_value = raw_value
        end

        # QMK数値コードに変換（サブクラスで実装）
        def to_qmk(keycode_converter, reference_converter: nil)
          raise NotImplementedError, "#{self.class} must implement #to_qmk"
        end

        # 文字列表現
        def to_s
          @raw_value
        end

        # Factory Method: YAML文字列から適切なサブクラスを生成
        def self.from_yaml(yaml_str)
          # nil または空文字列の場合は PlainKeycode として処理
          return PlainKeycode.new(raw_value: yaml_str) if yaml_str.nil? || yaml_str.to_s.empty?

          parsed = KeycodeParser.parse(yaml_str)

          case parsed[:type]
          when :reference, :legacy_macro, :legacy_tap_dance
            ReferenceKeycode.new(raw_value: yaml_str)
          when :function
            FunctionKeycode.new(raw_value: yaml_str)
          else
            # :keycode, :alias, :number, :string, :modifier_expression
            PlainKeycode.new(raw_value: yaml_str)
          end
        end

        # Factory Method: QMK数値コードから生成
        def self.from_qmk(qmk_code, keycode_converter, reference_converter: nil)
          # QMK → エイリアス（reference_converter経由で名前解決を試みる）
          if reference_converter
            # マクロ・タップダンス・コンボの逆解決を試行
            begin
              resolved_token = reference_converter.reverse_resolve_qmk(qmk_code)
              if resolved_token
                alias_str = KeycodeParser.unparse(resolved_token)
                return from_yaml(alias_str)
              end
            rescue StandardError
              # 解決失敗時は通常のエイリアス解決にフォールバック
            end
          end

          # 通常のキーコードエイリアス解決
          alias_str = keycode_converter.reverse_resolve(qmk_code)
          from_yaml(alias_str)
        end

        # サブクラス: PlainKeycode - 単純なキーコード
        class PlainKeycode < KeycodeValue
          def to_qmk(keycode_converter, reference_converter: nil)
            # modifier_expression の場合は ModifierExpressionCompiler に委譲
            parsed = KeycodeParser.parse(@raw_value)
            if parsed.is_a?(Hash) && parsed[:type] == :modifier_expression
              return ModifierExpressionCompiler.to_qmk(parsed, keycode_converter)
            end

            resolved = keycode_converter.resolve(@raw_value)
            if resolved.nil?
              raise ArgumentError, "Invalid keycode '#{@raw_value}': not found in aliases or QMK keycodes"
            end
            resolved
          end
        end

        # サブクラス: ReferenceKeycode - 参照形式（Macro, TapDance, Combo）
        class ReferenceKeycode < KeycodeValue
          def to_qmk(keycode_converter, reference_converter: nil)
            raise ArgumentError, "reference_converter is required for ReferenceKeycode" if reference_converter.nil?

            parsed = KeycodeParser.parse(@raw_value)

            # レガシー形式（M0, TD(2)）の場合はそのまま返す
            if parsed[:type] == :legacy_macro || parsed[:type] == :legacy_tap_dance
              return parsed[:value]
            end

            reference_converter.resolve(parsed)
          end
        end

        # サブクラス: FunctionKeycode - 関数形式（MO, LSFT, LT等）
        class FunctionKeycode < KeycodeValue
          def to_qmk(keycode_converter, reference_converter: nil)
            parsed = KeycodeParser.parse(@raw_value)
            resolve_function_to_qmk(parsed, keycode_converter, reference_converter)
          end

          private

          # 関数を再帰的にQMK形式に解決
          def resolve_function_to_qmk(parsed, keycode_converter, reference_converter)
            function_name = parsed[:name]
            args = parsed[:args]

            # 引数を再帰的に解決
            resolved_args = args.map do |arg|
              resolve_argument(arg, function_name, keycode_converter, reference_converter)
            end

            # 関数形式を構築
            "#{function_name}(#{resolved_args.join(', ')})"
          end

          # 引数を解決（再帰的）
          def resolve_argument(arg, function_name, keycode_converter, reference_converter)
            case arg[:type]
            when :number
              # レイヤー切り替え系の関数は数値をそのまま保持
              if function_name.match?(/^(MO|TO|OSL|TG|TT|DF|LT\d*|TD|COMBO)$/)
                arg[:value].to_s
              else
                # 修飾キー系の関数は数値を KC_* に変換
                "KC_#{arg[:value]}"
              end
            when :string
              # 文字列はそのまま
              arg[:value]
            when :keycode
              # QMKキーコード（KC_*）はそのまま
              arg[:value]
            when :alias
              # エイリアスを解決
              resolved = keycode_converter.resolve(arg[:value])
              if resolved.nil?
                raise ArgumentError, "Invalid keycode alias '#{arg[:value]}': not found in aliases"
              end
              resolved
            when :reference, :legacy_macro, :legacy_tap_dance
              # 参照を解決
              reference_converter.resolve(arg)
            when :function
              # ネストした関数を再帰的に解決
              resolve_function_to_qmk(arg, keycode_converter, reference_converter)
            else
              # その他（modifier_expression等）
              # とりあえずエイリアス解決を試みる
              keycode_converter.resolve(arg[:value] || arg.to_s)
            end
          end
        end
      end
    end
  end
end
