# frozen_string_literal: true

module Cornix
  module Interface
    module Cli
      # コマンドラインの指定の誤り（知らないコマンド・オプション、引数の過不足）
      class UsageError < Cornix::Error; end
    end
  end
end
