# frozen_string_literal: true

module Cornix
  # 例外の階層（新アーキテクチャの例外はすべてここで定義する）
  class Error < StandardError; end

  # 値オブジェクトの構造検証に失敗した（範囲外、型違い、必須項目なし）
  class InvalidValue < Error; end

  # 同梱データ（data/*.yaml）や設定ファイルの読み込みに失敗した
  class ConfigError < Error
    attr_reader :path

    def initialize(message, path: nil)
      @path = path
      super(path ? "#{path}: #{message}" : message)
    end
  end

  # キーコードを数値や文字列に変換できない
  class UnknownKeycode < Error; end

  # デバイスとの通信・プロトコルの失敗
  class DeviceError < Error; end

  # デバイスが使えない（読み書きを始める前に分かる失敗と、途中で応答がなくなったもの）。reason は次のどれか:
  #   :platform       macOS でない（raw HID のブリッジは macOS の IOKit を使う）
  #   :bridge         ブリッジ（ext/cornix_hid）をビルド・起動できない
  #   :not_connected  キーボードが見つからない・開けない
  #   :timeout        キーボードから応答がない・ブリッジが途中で終わった
  class DeviceUnavailable < DeviceError
    REASONS = %i[platform bridge not_connected timeout].freeze

    attr_reader :reason

    def initialize(message, reason:)
      raise ArgumentError, "知らない理由です: #{reason.inspect}" unless REASONS.include?(reason)

      @reason = reason
      super(message)
    end
  end

  # 書き込みの途中で失敗した（applied は書き終えた件数、backup は書く前に取ったバックアップ。なければ nil）
  class WriteIncomplete < DeviceError
    attr_reader :applied, :backup

    def initialize(message, applied:, backup: nil)
      @applied = applied
      @backup = backup
      super(message)
    end
  end

  # 目標のイメージをデバイスに書き込む計画を作れない（レイヤー数やマクロ数がデバイスの上限を超えるなど）
  class PlanError < Error; end

  # 計画が確認したとき（dry run の token）から変わった
  class PlanChanged < PlanError; end

  # 書き込みを拒否するキーコード（QK_BOOT など）を含む計画。keycodes はその表記
  class PlanRejected < PlanError
    attr_reader :keycodes

    def initialize(message, keycodes:)
      @keycodes = keycodes.dup.freeze
      super(message)
    end
  end
end
