# frozen_string_literal: true

require_relative 'checks'

module Cornix
  module Domain
    # config/metadata.yaml の内容。名前の付いた項目のほかは extra にそのまま持ち、往復で落とさない
    # （extra_keys（layout.vil の layout_options / alt_repeat_key / key_override）、file_naming、references など）。
    #
    #   keyboard            必須。空でない文字列
    #   version             必須。整数（layout.vil の version）
    #   uid                 整数（layout.vil の uid）
    #   vendor_product_id   "0xXXXX"
    #   product_id          そのまま
    #   matrix              { 'rows' => 正の整数, 'cols' => 正の整数 }
    #   vial_protocol / via_protocol   整数
    class Metadata < Data.define(:keyboard, :version, :uid, :vendor_product_id, :product_id, :matrix,
                                 :vial_protocol, :via_protocol, :extra)
      FIELDS = %w[keyboard version uid vendor_product_id product_id matrix vial_protocol via_protocol].freeze
      VENDOR_PRODUCT_ID = /\A0x\h{4}\z/

      # metadata.yaml を読み込んだ Hash から作る（キーは文字列）
      def self.from_h(hash)
        raise InvalidValue, "metadata は Hash です: #{hash.inspect}" unless hash.is_a?(Hash)

        known = FIELDS.to_h { |f| [f.to_sym, hash[f]] }
        new(**known, extra: hash.reject { |k, _| FIELDS.include?(k) })
      end

      def initialize(keyboard:, version:, uid: nil, vendor_product_id: nil, product_id: nil, matrix: nil,
                     vial_protocol: nil, via_protocol: nil, extra: {})
        super(
          keyboard: Checks.name!(keyboard, 'keyboard'),
          version: check_integer!(version, 'version', required: true),
          uid: check_integer!(uid, 'uid'),
          vendor_product_id: check_vendor_product_id!(vendor_product_id),
          product_id: deep_freeze(product_id),
          matrix: check_matrix!(matrix),
          vial_protocol: check_integer!(vial_protocol, 'vial_protocol'),
          via_protocol: check_integer!(via_protocol, 'via_protocol'),
          extra: check_extra!(extra)
        )
      end

      # layout.vil の layout_options / alt_repeat_key / key_override（なければ空の Hash）
      def extra_keys = extra.fetch('extra_keys', {})

      # metadata.yaml の形の Hash（nil の項目は省く。extra は後ろに元の順で付ける）
      def to_h
        FIELDS.to_h { |f| [f, public_send(f)] }.compact.merge(extra)
      end

      private

      def check_integer!(value, what, required: false)
        return nil if value.nil? && !required
        return value if value.is_a?(Integer) && value >= 0

        raise InvalidValue, "#{what}は 0 以上の整数です: #{value.inspect}"
      end

      def check_vendor_product_id!(value)
        return nil if value.nil?
        return value.dup.freeze if value.is_a?(String) && value.match?(VENDOR_PRODUCT_ID)

        raise InvalidValue, "vendor_product_id は 0xXXXX の形です: #{value.inspect}"
      end

      def check_matrix!(value)
        return nil if value.nil?

        Checks.hash!(value, 'matrix') do |key, n|
          next unless %w[rows cols].include?(key)
          next if n.is_a?(Integer) && n.positive?

          raise InvalidValue, "matrix.#{key} は正の整数です: #{n.inspect}"
        end
        deep_freeze(value)
      end

      def check_extra!(value)
        Checks.hash!(value, 'metadata の他の項目') do |key, _|
          raise InvalidValue, "metadata の項目名は文字列です: #{key.inspect}" unless key.is_a?(String)
          raise InvalidValue, "#{key} は extra ではなく引数で渡します" if FIELDS.include?(key)
        end
        deep_freeze(value)
      end

      def deep_freeze(value)
        case value
        when Hash then value.to_h { |k, v| [deep_freeze(k), deep_freeze(v)] }.freeze
        when Array then value.map { |v| deep_freeze(v) }.freeze
        when String then value.dup.freeze
        else value
        end
      end
    end
  end
end
