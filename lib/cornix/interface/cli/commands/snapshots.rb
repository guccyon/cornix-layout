# frozen_string_literal: true

require 'pathname'
require_relative '../command'

module Cornix
  module Interface
    module Cli
      module Commands
        # cornix snapshots [--kind KIND]: キーボードの状態と compile の出力の履歴（tmp/snapshots/）を新しい順に表示する。
        # パスは cornix restore / device diff / decompile にそのまま渡せる（カレントの下なら相対パス）
        class Snapshots < Command
          command 'snapshots', 'キーボードの状態と compile の出力の履歴（日時・種類・パス）を新しい順に表示する',
                  args: '[--kind KIND]'

          def self.help
            <<~TEXT.chomp
              #{super}

              種類（KIND）:
                read         キーボードを読んだとき（pull / init / status / apply / restore / device read / device diff）
                build        compile の出力
                backup       cornix device backup で保存したとき
                pre-apply    apply で書き込む直前（cornix restore の既定の戻し先）
                pre-restore  restore で書き込む直前
                legacy       前の版のバックアップ（tmp/device_backups/）

              read と build は種類ごとに新しい #{Application::ListSnapshots::KEEP} 件だけ残します。
            TEXT
          end

          def run(args)
            _, opts = parse!(args) { |p, o| p.on('--kind KIND', '種類で絞り込む') { |k| o[:kind] = k } }
            kind = opts[:kind]
            list = use_case(:list_snapshots).call(kind: kind)
            return none(kind) if list.empty?

            width = list.snapshots.map { |s| s.kind.size }.max
            list.snapshots.each do |snapshot|
              out.line("#{snapshot.time.strftime('%Y-%m-%d %H:%M:%S')}  #{snapshot.kind.ljust(width)}  #{display(snapshot.path)}")
            end
            SUCCESS
          end

          private

          def none(kind)
            out.line(kind ? "種類 #{kind} のスナップショットはありません" : 'スナップショットはありません')
            SUCCESS
          end

          # カレントの下なら相対パス、外なら絶対パス
          def display(path)
            relative = Pathname(path).expand_path.relative_path_from(Pathname(Dir.pwd).expand_path).to_s
            outside = relative == '..' || relative.start_with?("..#{File::SEPARATOR}")
            outside ? File.expand_path(path) : relative
          end
        end
      end
    end
  end
end
