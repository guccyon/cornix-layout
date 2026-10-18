# frozen_string_literal: true

module Cornix
  module Mapping
    # キーコードの名前と 16bit 値の対応表（data/keycodes.yaml と data/aliases.yaml）。
    # 読み込み時に Hash を作って freeze し、以降は引くだけ。名前の大文字小文字は区別する。
    #
    #   KeycodeCatalog.default                     同梱の表（プロセスで 1 回だけ読む）
    #   KeycodeCatalog.load(custom_keycodes: [..]) キーボード定義の customKeycodes（BT0 など）を USER00.. の別名として足す
    class KeycodeCatalog
      FIELDS = %i[qmk_names names_by_code vial_names aliases aliases_by_code preferred basic quantum dangerous_ranges
                 unsupported_ranges].freeze

      # 通常は Loader が作る。引数はすべて読み込み済みの Hash / Set
      def initialize(**tables)
        missing = FIELDS - tables.keys
        raise ArgumentError, "missing: #{missing.join(', ')}" unless missing.empty?

        tables.each { |name, value| instance_variable_set(:"@#{name}", value.freeze) }
        freeze
      end

      # Vial / QMK の名前（name と qmk）→ 値。shifted の名前（KC_EXLM など）も含む
      def code_for_name(name) = @qmk_names[name]

      # 人が読む別名 → 値（data/aliases.yaml。modified の別名なら修飾付きの値）
      def code_for_alias(name) = @aliases[name]

      # 名前か別名 → 値（どちらにもなければ nil）
      def lookup(name) = @qmk_names[name] || @aliases[name]

      # 値 → 設定ファイルに書く名前（special / basic / quantum の name。なければ nil）
      def name(code) = @names_by_code[code]

      # 値 → .vil に書く Vial 名（name のうち Vial GUI に名前があるもの。なければ nil）
      def vial_name(code) = @vial_names[code]

      # 値 → 正規の別名（別名リストの先頭。なければ nil）
      def preferred_alias(code) = @preferred[code]

      # 値 → その値のすべての別名
      def aliases_for(code) = @aliases_by_code.fetch(code, EMPTY)

      def basic?(code) = @basic.include?(code)

      def quantum?(code) = @quantum.include?(code)

      # 書き込みを拒否する値か
      def dangerous?(code) = !dangerous_reason(code).nil?

      # 書き込みを拒否する理由（拒否しない値なら nil）
      def dangerous_reason(code) = @dangerous_ranges.find { |range, _| range.cover?(code) }&.last

      # Cornix が対応していないとみられる理由（data/unsupported_keycodes.yaml。対応していれば nil）
      def unsupported_reason(code) = @unsupported_ranges.find { |range, _| range.cover?(code) }&.last

      # Cornix が対応していないとみられる値 => 「名前: 理由」（Domain::Capabilities#unsupported_keycodes に渡す）
      def unsupported_keycodes
        @unsupported_ranges.flat_map do |range, reason|
          range.map { |code| [code, "#{name(code) || format('0x%04X', code)}: #{reason}"] }
        end.to_h
      end

      def names = @qmk_names.keys + @aliases.keys

      EMPTY = [].freeze
      private_constant :EMPTY

      def self.default = @default ||= Loader.new.load

      def self.load(**opts) = Loader.new(**opts).load
    end
  end
end
