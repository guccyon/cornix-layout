# frozen_string_literal: true

module Cornix
  module Application
    module Editor
      # エディタのサーバーで、指定されたプロファイル（設定ディレクトリの dir か、開いたときの profileId）が分からない。
      # dir と profile_id のどちらか一方を持つ（Interface が JSON-RPC のエラーの data にする）
      class ProfileNotFound < Cornix::Error
        attr_reader :dir, :profile_id

        def initialize(dir: nil, profile_id: nil)
          @dir = dir
          @profile_id = profile_id
          super(dir ? "プロファイルが見つかりません: #{dir}" : "開いていないプロファイルです: #{profile_id}")
        end
      end
    end
  end
end
