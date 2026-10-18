# frozen_string_literal: true

require_relative 'checks'
require_relative 'keycode'

module Cornix
  module Domain
    # 名前付きショートカット（名前 => Keycode。config/shortcuts.yaml）。
    # 名前は空でない文字列で、前後の空白を除いて一意。定義順を保つ
    class ShortcutLibrary < Data.define(:entries)
      def initialize(entries: {})
        raise InvalidValue, "ショートカットは { 名前 => Keycode } です: #{entries.inspect}" unless entries.is_a?(Hash)

        normalized = {}
        entries.each do |name, keycode|
          key = Checks.name!(name, 'ショートカットの名前').strip.freeze
          raise InvalidValue, "ショートカットの名前が重複しています: #{key.inspect}" if normalized.key?(key)

          normalized[key] = Keycode.check!(keycode, "ショートカット #{key.inspect} のキーコード")
        end
        super(entries: normalized.freeze)
      end

      def names = entries.keys
      def empty? = entries.empty?

      EMPTY = new
    end
  end
end
