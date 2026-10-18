# frozen_string_literal: true

require_relative 'use_case'

module Cornix
  module Application
    # バックアップを新しい順に返す（デバイス不要）→ BackupList
    class ListBackups < UseCase
      def call = BackupList.new(dir: env.backup_store.dir, paths: env.backup_store.list)
    end
  end
end
