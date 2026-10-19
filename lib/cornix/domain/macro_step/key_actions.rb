# frozen_string_literal: true

require_relative 'tap'
require_relative 'down'
require_relative 'up'

module Cornix
  module Domain
    module MacroStep
      # 設定ファイル（macros/ の sequence、data/shortcuts/ の macro:）の action の名前 → キーを押す系の命令のクラス
      KEY_ACTIONS = { 'tap' => Tap, 'down' => Down, 'up' => Up }.freeze
    end
  end
end
