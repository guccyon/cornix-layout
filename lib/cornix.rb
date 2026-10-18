# frozen_string_literal: true

# 新アーキテクチャのローダー。
# lib/cornix/{LAYERS}/**/*.rb をレイヤーの順・パスの浅い順・アルファベット順に require する。
# クラス定義の時点で必要な定数は、そのファイルの先頭で require_relative すること。
module Cornix
  ROOT = File.expand_path('..', __dir__)
  DATA_DIR = File.join(ROOT, 'data')
  LAYERS = %w[domain image mapping planning storage device application interface].freeze
end

require_relative 'cornix/errors'

Cornix::LAYERS.each do |layer|
  Dir[File.join(__dir__, 'cornix', layer, '**', '*.rb')]
    .sort_by { |path| [path.count('/'), path] }
    .each { |path| require path }
end
