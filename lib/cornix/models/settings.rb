# frozen_string_literal: true

require_relative 'concerns/validatable'

module Cornix
  module Models
    # QMK/Vial設定を保持するモデル
    #
    # YAML形式（人間可読）とVial QMKインデックス形式（整数キー）を相互変換する。
    #
    # YAML形式（config/settings/qmk_settings.yaml）:
    #   keyboard:
    #     tapping_term: 250
    #     chordal_hold: true
    #   vial:
    #     combo_timing_window: 50
    #
    # Vial QMKインデックス形式（layout.vil）:
    #   { 7 => 250, 22 => 1, 2 => 50, ... }
    #
    # インデックスはVial QMKプロトコルのQMK_SETTINGS配列に対応する。
    # 参考: https://github.com/vial-kb/vial-qmk/blob/vial/quantum/vial.c
    class Settings
      include Concerns::Validatable

      attr_reader :settings_hash

      # Vial QMK設定インデックスのマッピング
      # キー: YAML上の設定名 (keyboard.*またはvial.*)
      # 値: Vial QMKプロトコルの整数インデックス
      VIAL_QMK_INDEX = {
        'keyboard' => {
          'oneshot_timeout'         => 6,
          'tapping_term'            => 7,
          'tap_code_delay'          => 18,
          'tap_hold_caps_delay'     => 19,
          'chordal_hold'            => 22,   # boolean
          'permissive_hold'         => 23,   # boolean
          'hold_on_other_key_press' => 26,   # boolean
          'flow_tap'                => 27,
        },
        'vial' => {
          'combo_timing_window'     => 2,
        }
      }.freeze

      # Structural validation: settings_hash must be a Hash
      validates :settings_hash, :type, is: Hash

      def initialize(settings_hash)
        @settings_hash = settings_hash || {}
      end

      # QMK Hash（整数インデックス形式）→ Settings
      def self.from_qmk(hash)
        new(hash)
      end

      # Settings → Vial QMK Hash（整数インデックス形式）
      #
      # YAML形式（keyboard/vialネスト）を整数インデックス形式に変換する。
      # from_qmkで読み込んだ場合（既に整数インデックス形式）はそのまま返す。
      def to_qmk
        # keyboard/vialキーを持つYAML形式の場合は変換
        return yaml_to_qmk_index if yaml_format?

        # 既に整数インデックス形式（from_qmk経由）はそのまま返す
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

      # Settings → YAML Hash（人間可読形式）
      def to_yaml_hash
        @settings_hash
      end

      private

      # YAML形式（keyboard/vialネスト）かどうか判定
      def yaml_format?
        @settings_hash.key?('keyboard') || @settings_hash.key?('vial')
      end

      # YAML形式 → Vial QMK整数インデックス形式に変換
      def yaml_to_qmk_index
        result = {}

        VIAL_QMK_INDEX.each do |group, mappings|
          group_hash = @settings_hash[group]
          next unless group_hash.is_a?(Hash)

          mappings.each do |setting_name, index|
            next unless group_hash.key?(setting_name)

            value = group_hash[setting_name]
            # boolean を 0/1 に変換
            value = value ? 1 : 0 if value == true || value == false
            result[index] = value
          end
        end

        result
      end
    end
  end
end
