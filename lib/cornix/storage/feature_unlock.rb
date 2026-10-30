# frozen_string_literal: true

module Cornix
  module Storage
    # 解放されている機能。今は手元にファイルがあれば全部を解放する（将来はキーを検証して決める）
    #
    #   FeatureUnlock.unlocked  #=> ['editor.byKey'] か []
    module FeatureUnlock
      FEATURES = %w[editor.byKey].freeze

      module_function

      def unlocked(env: ENV)
        File.file?(path(env)) ? FEATURES : []
      end

      def path(env)
        base = env['XDG_CONFIG_HOME'].to_s.empty? ? File.join(Dir.home, '.config') : env['XDG_CONFIG_HOME']
        File.join(base, 'cornix', 'unlock')
      end
    end
  end
end
