# frozen_string_literal: true

require_relative 'checks'

module Cornix
  module Domain
    # 意味検証の結果 1 件。path はモデル内のパス（例: "layers[0].left_hand.row0.tab"、"macros[2].steps[1]"）。
    # layers[i] などの番号は Profile の配列の位置。ファイル上の位置への写像は Storage が行う
    class Diagnostic < Data.define(:severity, :path, :message)
      SEVERITIES = %i[error warning].freeze

      def initialize(severity:, path:, message:)
        Checks.one_of!(severity, SEVERITIES, 'severity')
        super(severity: severity, path: path.to_s.dup.freeze, message: message.to_s.dup.freeze)
      end

      def error? = severity == :error
      def warning? = severity == :warning
      def to_s = "[#{severity}] #{path}: #{message}"

      def self.error(path, message) = new(severity: :error, path: path, message: message)
      def self.warning(path, message) = new(severity: :warning, path: path, message: message)
    end
  end
end
