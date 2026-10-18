# frozen_string_literal: true

module Cornix
  module Application
    # Init の結果。
    #   config_dir     作った設定ディレクトリ
    #   created        作ったもの（root からの相対パス。.gitignore に行を足したときはその旨）
    #   imported_from  設定を書いた元（:device か .vil のパス）。書かなかったら nil
    #   files          書いた設定ファイル（config_dir からの相対パス）
    #   device_error   デバイスにつながらなかった理由（つながったか、読まなかったなら nil）
    #   notes          利用者への案内
    class InitResult < Data.define(:config_dir, :created, :imported_from, :files, :device_error, :notes)
      def initialize(config_dir:, created: [], imported_from: nil, files: [], device_error: nil, notes: []) = super

      def imported? = !imported_from.nil?

      def to_h
        { 'config_dir' => config_dir, 'created' => created, 'imported_from' => imported_from&.to_s,
          'files' => files, 'device_error' => device_error, 'notes' => notes }
      end
    end
  end
end
