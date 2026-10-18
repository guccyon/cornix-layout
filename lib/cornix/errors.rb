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

  # 目標のイメージをデバイスに書き込む計画を作れない（レイヤー数やマクロ数がデバイスの上限を超えるなど）
  class PlanError < Error; end
end
