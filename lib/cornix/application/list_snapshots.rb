# frozen_string_literal: true

require_relative 'use_case'

module Cornix
  module Application
    # スナップショットを新しい順に返す（デバイス不要。kind で絞り込める）→ SnapshotList
    class ListSnapshots < UseCase
      # 絞り込みに使える種類（CLI と MCP が使う）と、種類ごとに残す件数の上限（read と build だけ）
      KINDS = [*Storage::SnapshotStore::KINDS, Storage::SnapshotStore::LEGACY].freeze
      KEEP = Storage::SnapshotStore::KEEP

      def call(kind: nil)
        store = env.snapshot_store
        SnapshotList.new(dir: store.dir, snapshots: store.list(kind: kind))
      end
    end
  end
end
