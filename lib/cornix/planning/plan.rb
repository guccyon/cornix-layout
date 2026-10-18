# frozen_string_literal: true

require 'digest'
require 'json'

module Cornix
  module Planning
    # 書き込む変更の列と確認用の token。warnings は書き込みを止めない注意（無視する位置など）
    class Plan < Data.define(:changes, :warnings)
      def initialize(changes:, warnings: [])
        changes.each do |c|
          raise ArgumentError, "Change ではありません: #{c.inspect}" unless c.is_a?(Change::Value)
        end
        super(changes: changes.dup.freeze, warnings: warnings.map { |w| w.to_s.dup.freeze }.freeze)
      end

      def empty? = changes.empty?

      def size = changes.size

      def each(&) = changes.each(&)

      # 書き込む内容のハッシュ（16 桁）。dry run で示し、適用時に計画し直した token と一致することを確かめる
      def token = Digest::SHA256.hexdigest(JSON.generate(changes.map(&:token_payload)))[0, 16]
    end
  end
end
