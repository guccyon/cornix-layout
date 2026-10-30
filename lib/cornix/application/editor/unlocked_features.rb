# frozen_string_literal: true

module Cornix
  module Application
    module Editor
      # 解放されている機能の名前の一覧（features/status）
      class UnlockedFeatures
        def initialize(env: ENV)
          @env = env
        end

        def call = Storage::FeatureUnlock.unlocked(env: @env)
      end
    end
  end
end
