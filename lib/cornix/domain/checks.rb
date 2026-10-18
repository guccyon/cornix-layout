# frozen_string_literal: true

module Cornix
  module Domain
    # 値オブジェクトの構造検証で使う小さな関数群。失敗したら InvalidValue を送出する。
    module Checks
      module_function

      def integer!(value, range, what)
        return value if value.is_a?(Integer) && range.cover?(value)

        raise InvalidValue, "#{what}は #{range.begin}〜#{range.end} の整数です: #{value.inspect}"
      end

      def instance!(value, klass, what)
        return value if value.is_a?(klass)

        raise InvalidValue, "#{what}は #{klass.name.split('::').last} です: #{value.inspect}"
      end

      def one_of!(value, choices, what)
        return value if choices.include?(value)

        raise InvalidValue, "#{what}は #{choices.join(' / ')} のどれかです: #{value.inspect}"
      end

      def name!(value, what)
        return value.dup.freeze if value.is_a?(String) && !value.strip.empty?

        raise InvalidValue, "#{what}は空でない文字列です: #{value.inspect}"
      end

      def text(value, what)
        return nil if value.nil?
        return value.dup.freeze if value.is_a?(String)

        raise InvalidValue, "#{what}は文字列です: #{value.inspect}"
      end

      def list!(value, what, &each)
        raise InvalidValue, "#{what}は配列です: #{value.inspect}" unless value.is_a?(Array)

        value.each_with_index { |item, i| each&.call(item, i) }
        value.dup.freeze
      end

      # Hash を検査し、freeze した複製を返す（each には key, value を渡す）
      def hash!(value, what, &each)
        raise InvalidValue, "#{what}は Hash です: #{value.inspect}" unless value.is_a?(Hash)

        value.each { |k, v| each&.call(k, v) }
        value.dup.freeze
      end
    end
  end
end
