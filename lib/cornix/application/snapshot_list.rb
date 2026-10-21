# frozen_string_literal: true

module Cornix
  module Application
    # ListSnapshots の結果（Storage::SnapshotStore::Snapshot を新しい順に）
    class SnapshotList < Data.define(:dir, :snapshots)
      def initialize(dir:, snapshots:) = super(dir: dir, snapshots: snapshots.dup.freeze)

      def empty? = snapshots.empty?
      def paths = snapshots.map(&:path)
      def to_h = { 'dir' => dir, 'snapshots' => snapshots.map(&:to_h) }
    end
  end
end
