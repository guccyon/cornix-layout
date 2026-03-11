# frozen_string_literal: true

module Cornix
  module Models
    # QMK設定を透過的に保持するモデル
    class Settings
      attr_reader :settings_hash

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
        new(hash)
      end

      # Settings → YAML Hash
      def to_yaml_hash
        @settings_hash
      end
    end
  end
end
