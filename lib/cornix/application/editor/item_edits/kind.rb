# frozen_string_literal: true

module Cornix
  module Application
    module Editor
      class ItemEdits
        # ファイル 1 つで 1 件の項目の種類（約束の kind の文字列ごと）。
        #   collection  Domain::Profile の一覧（macros など。モデル内のパス "macros[0]" の頭にもなる）
        #   files       Storage::ConfigFiles の種類（ディレクトリと番号の桁数）
        #   function    名前で参照する関数（Macro('名前')。参照されないものは nil）
        #   keys        ファイルのトップレベルの項目の並び（Schema::*File.write が書く順。name を足すときの場所）
        #   fallback    名前から英数字が残らないときのファイル名
        Kind = Data.define(:name, :label, :collection, :files, :function, :keys, :fallback) do
          def directory = Storage::ConfigFiles.directory(files)

          def digits = Storage::ConfigFiles::KINDS.fetch(files)[1]

          def items(profile) = profile.public_send(collection)

          def limit(capabilities) = capabilities.public_send(collection)
        end

        KINDS = {
          'macro' => Kind.new(name: 'macro', label: 'マクロ', collection: :macros, files: :macros, function: 'Macro',
                              keys: %w[index name description sequence preset], fallback: 'macro'),
          'tapDance' => Kind.new(name: 'tapDance', label: 'タップダンス', collection: :tap_dances, files: :tap_dances,
                                 function: 'TapDance', keys: %w[index name description actions tapping_term], fallback: 'tap_dance'),
          'combo' => Kind.new(name: 'combo', label: 'コンボ', collection: :combos, files: :combos, function: nil,
                              keys: %w[index name description trigger_keys output_key], fallback: 'combo'),
          'layer' => Kind.new(name: 'layer', label: 'レイヤー', collection: :layers, files: :layers, function: nil,
                              keys: %w[name description index mapping], fallback: 'layer')
        }.freeze
      end
    end
  end
end
