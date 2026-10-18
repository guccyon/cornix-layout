# frozen_string_literal: true

module Cornix
  module Application
    # Cleanup の結果。status は
    #   :nothing    消すものがない
    #   :protected  .decompile.lock があり force でないので何もしなかった
    #   :cancelled  force で確認したが中止した
    #   :cleaned    消した（deleted は消したもの: "config/", "layout.vil"）
    # lock は .decompile.lock の内容（なければ nil）
    class CleanupResult < Data.define(:status, :lock, :deleted)
      def initialize(status:, lock: nil, deleted: []) = super
    end
  end
end
