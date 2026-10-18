# frozen_string_literal: true

module Cornix
  module Application
    # rename の 1 件（旧 rename_plans.json の 1 要素）。
    #   old_path: 変える設定ファイル（config/macros/00_macro.yml、macros/00_macro.yml、絶対パスのどれでもよい）
    #   new_basename: 新しいファイル名（番号の接頭辞 00_ は元と同じにする）
    #   content_updates: 書き換えるトップレベルの項目（{ 'name' => ..., 'description' => ... }）
    class RenamePlan < Data.define(:old_path, :new_basename, :content_updates, :reasoning, :confidence)
      # 種類 => 設定ディレクトリの中のディレクトリ名
      TYPES = { 'macro' => 'macros', 'tap_dance' => 'tap_dance', 'combo' => 'combos', 'layer' => 'layers' }.freeze

      def initialize(old_path:, new_basename:, content_updates: {}, reasoning: nil, confidence: nil)
        updates = (content_updates || {}).to_h.transform_keys(&:to_s).freeze
        super(old_path: old_path&.to_s, new_basename: new_basename&.to_s, content_updates: updates,
              reasoning: reasoning, confidence: confidence)
      end

      # 文字列キーでもシンボルキーでもよい Hash から作る
      def self.from_h(hash)
        h = hash.to_h.transform_keys(&:to_s)
        new(old_path: h['old_path'], new_basename: h['new_basename'], content_updates: h['content_updates'] || {},
            reasoning: h['reasoning'], confidence: h['confidence'])
      end

      # 'macro' / 'tap_dance' / 'combo' / 'layer' / 'unknown'
      def type
        dirs = old_path.to_s.split('/')[0...-1]
        TYPES.find { |_, dir| dirs.include?(dir) }&.first || 'unknown'
      end

      def name = content_updates['name']
      def description = content_updates['description']
      def old_basename = File.basename(old_path.to_s)

      def to_h = { 'old_path' => old_path, 'new_basename' => new_basename, 'content_updates' => content_updates.dup }
    end
  end
end
