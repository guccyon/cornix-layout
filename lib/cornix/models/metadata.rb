# frozen_string_literal: true

require_relative 'concerns/validatable'

module Cornix
  module Models
    # キーボードメタデータを保持するモデル
    class Metadata
      include Concerns::Validatable

      attr_reader :keyboard, :version, :uid, :vendor_product_id, :product_id,
                  :matrix, :vial_protocol, :via_protocol

      # === バリデーション定義（宣言的）===

      validates :keyboard, :presence, message: "cannot be blank"
      validates :version, :type, is: Integer, message: "must be an integer"
      # uid は Integer または String を許容（実際にはInteger/StringのどちらもあるHASH値）

      validates :vendor_product_id, :format,
                with: /^0x[0-9A-Fa-f]{4}$/,
                message: "format invalid (expected 0xXXXX)",
                allow_nil: true

      validates :vial_protocol, :type, is: Integer, allow_nil: true
      validates :via_protocol, :type, is: Integer, allow_nil: true

      # カスタムバリデーション（matrix構造）
      validates :matrix, :custom, with: ->(value) {
        return { valid: true } if value.nil?

        errors = []
        unless value.is_a?(Hash)
          return { valid: false, error: "must be a hash" }
        end

        if value['rows']
          errors << "matrix.rows must be an integer" unless value['rows'].is_a?(Integer)
          errors << "matrix.rows must be positive" if value['rows'].is_a?(Integer) && value['rows'] <= 0
        end

        if value['cols']
          errors << "matrix.cols must be an integer" unless value['cols'].is_a?(Integer)
          errors << "matrix.cols must be positive" if value['cols'].is_a?(Integer) && value['cols'] <= 0
        end

        if errors.empty?
          { valid: true }
        else
          { valid: false, error: errors.join(", ") }
        end
      }, field_name: "matrix"

      def initialize(
        keyboard:,
        version:,
        uid:,
        vendor_product_id:,
        product_id:,
        matrix:,
        vial_protocol:,
        via_protocol:
      )
        # 基本的なnilチェック（fail fast）
        raise ArgumentError, "keyboard cannot be nil" if keyboard.nil?
        raise ArgumentError, "version cannot be nil" if version.nil?
        # uid は nil を許容（実装上はあるがなくてもいい）

        @keyboard = keyboard
        @version = version
        @uid = uid
        @vendor_product_id = vendor_product_id
        @product_id = product_id
        @matrix = matrix  # { 'rows' => 8, 'cols' => 7 }
        @vial_protocol = vial_protocol
        @via_protocol = via_protocol
      end

      # QMK Hash → Metadata
      def self.from_qmk(hash)
        new(
          keyboard: 'Cornix',  # 固定値（QMKには含まれない）
          version: hash['version'],
          uid: hash['uid'],
          vendor_product_id: hash['vendor_product_id'],
          product_id: hash['product_id'],
          matrix: hash['matrix'],
          vial_protocol: hash['vial_protocol'],
          via_protocol: hash['via_protocol']
        )
      end

      # Metadata → QMK Hash
      def to_qmk
        result = {
          'version' => @version,
          'uid' => @uid,
          'vial_protocol' => @vial_protocol,
          'via_protocol' => @via_protocol
        }

        # nilでない値のみ追加
        result['vendor_product_id'] = @vendor_product_id if @vendor_product_id
        result['product_id'] = @product_id if @product_id
        result['matrix'] = @matrix if @matrix

        result
      end

      # YAML Hash → Metadata
      def self.from_yaml_hash(hash)
        # メタ情報抽出（存在する場合）
        metadata = hash.respond_to?(:__metadata) ? hash.__metadata : {}

        instance = new(
          keyboard: hash['keyboard'],
          version: hash['version'],
          uid: hash['uid'],
          vendor_product_id: hash['vendor_product_id'],
          product_id: hash['product_id'],
          matrix: hash['matrix'],
          vial_protocol: hash['vial_protocol'],
          via_protocol: hash['via_protocol']
        )

        # メタ情報保存
        instance.instance_variable_set(:@metadata, metadata)

        instance
      rescue ArgumentError => e
        raise ArgumentError, "Failed to create Metadata from YAML: #{e.message}"
      end

      # Metadata → YAML Hash
      def to_yaml_hash
        {
          'keyboard' => @keyboard,
          'version' => @version,
          'uid' => @uid,
          'vendor_product_id' => @vendor_product_id,
          'product_id' => @product_id,
          'matrix' => @matrix,
          'vial_protocol' => @vial_protocol,
          'via_protocol' => @via_protocol
        }
      end
    end
  end
end
