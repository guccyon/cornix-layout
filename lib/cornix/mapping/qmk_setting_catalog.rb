# frozen_string_literal: true

require 'yaml'

module Cornix
  module Mapping
    # QMK Settings（QSID）の定義表（data/qmk_settings.yaml）
    class QmkSettingCatalog
      # 1 つの設定の定義。description（説明）と default（既定値）は書いていなければ nil。
      # default はプロファイルのファイルと同じ形（boolean は true / false、integer は 0〜max）で、違えば ArgumentError
      class Definition < Data.define(:qsid, :name, :group, :width, :type, :description, :default)
        def initialize(qsid:, name:, group:, width:, type:, description: nil, default: nil)
          super
          unless description.nil? || description.is_a?(String)
            raise ArgumentError, "#{name} の description は文字列にしてください: #{description.inspect}"
          end
          return if default.nil? || valid_value?(default)

          raise ArgumentError, "#{name} の default が型と幅に合いません: #{default.inspect}"
        end

        def boolean? = type == 'boolean'

        def max = width == 1 ? 1 : (1 << (8 * width)) - 1

        private

        def valid_value?(value)
          boolean? ? [true, false].include?(value) : value.is_a?(Integer) && value.between?(0, max)
        end
      end

      def self.default = @default ||= load

      def self.load(path = File.join(Cornix::DATA_DIR, 'qmk_settings.yaml'))
        data = YAML.safe_load_file(path)
        new(data.fetch('settings').map { |h| Definition.new(**h.transform_keys(&:to_sym)) })
      rescue Errno::ENOENT, Psych::Exception, KeyError, ArgumentError => e
        raise ConfigError.new(e.message, path: path)
      end

      def initialize(definitions)
        @by_qsid = definitions.to_h { |d| [d.qsid, d] }.freeze
        @by_name = definitions.to_h { |d| [[d.group, d.name], d] }.freeze
        raise ConfigError, 'QSID が重複しています' if @by_qsid.size != definitions.size

        freeze
      end

      def all = @by_qsid.values

      def fetch(qsid) = @by_qsid[qsid]

      def find(group, name) = @by_name[[group, name]]

      def qsids = @by_qsid.keys
    end
  end
end
