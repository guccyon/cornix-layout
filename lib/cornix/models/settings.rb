# frozen_string_literal: true

require_relative 'concerns/validatable'

module Cornix
  module Models
    # QMK設定を透過的に保持するモデル
    class Settings
      include Concerns::Validatable

      attr_reader :settings_hash

      # Structural validation: settings_hash must be a Hash
      validates :settings_hash, :type, is: Hash

      def initialize(settings_hash)
        @settings_hash = settings_hash || {}
      end

      # QMK Hash → Settings
      def self.from_qmk(hash)
        new(hash)
      end

      # Settings → QMK Hash
      def to_qmk
        @settings_hash
      end

      # YAML Hash → Settings
      def self.from_yaml_hash(hash)
        # メタ情報抽出（存在する場合）
        metadata = hash.respond_to?(:__metadata) ? hash.__metadata : {}

        instance = new(hash)

        # メタ情報保存
        instance.instance_variable_set(:@metadata, metadata)

        instance
      end

      # Settings → YAML Hash
      def to_yaml_hash
        @settings_hash
      end
    end
  end
end
