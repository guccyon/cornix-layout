# frozen_string_literal: true

require_relative 'checks'
require_relative 'keycode'

module Cornix
  module Domain
    # コンボ 1 件。trigger_keys を同時に押すと output_key を送る。
    # index はデバイスのコンボの番号（0〜255）。トリガーの数・件数の上限、番号・名前の重複は
    # Profile#diagnostics で検査する
    class Combo < Data.define(:index, :name, :description, :trigger_keys, :output_key)
      INDEX_RANGE = (0..255)

      def initialize(index:, name:, trigger_keys:, output_key:, description: nil)
        super(
          index: Checks.integer!(index, INDEX_RANGE, 'コンボの番号'),
          name: Checks.name!(name, 'コンボの名前'),
          description: Checks.text(description, 'コンボの説明'),
          trigger_keys: check_triggers!(trigger_keys),
          output_key: Keycode.check!(output_key, 'コンボの出力')
        )
      end

      def to_s = "Combo(#{index}: #{name})"

      private

      def check_triggers!(keys)
        list = Checks.list!(keys, 'コンボのトリガー') { |k, i| Keycode.check!(k, "コンボのトリガー[#{i}]") }
        raise InvalidValue, 'コンボのトリガーが空です' if list.empty?

        list
      end
    end
  end
end
