# frozen_string_literal: true

require_relative 'operation'

module Cornix
  module Application
    module Editor
      class ItemEdits
        # 位置の名前を変える（protocol.md の 12.5 の renamePosition）。position_map.yaml のその位置の名前（並びの 1 要素）と、
        # すべてのレイヤーのファイル（未使用のものも）の mapping の下のその名前のキーを書き換える（書いていないレイヤーはそのまま）。
        # compile の結果は変わらないはずだが、名前の変更と同じく前後を照合する。新しい名前が今と同じなら何もしない
        class RenamePosition < Operation
          def requires_complete? = true

          private

          def run(edit)
            map = profile.position_map
            position = position_of(edit)
            found = map.symbol(position) or
              raise InvalidChange.new('edit', "position_map にない位置です: #{edit.hand} #{edit.row} #{edit.col}")
            group, symbol = found
            return outcome if edit.to == symbol

            hand = map.hand_key(position)
            symbols = map.symbols(hand, group)
            check_symbol!(edit.to, symbols)
            file = position_map_file
            path = [hand, group, symbols.index(symbol)]
            edit_file(file) { |text| Storage::YamlDocument.parse(text).replace(path, edit.to) }
            rename_layer_keys(['mapping', hand, group, symbol], edit.to)
            outcome(verify: { file: file, path: path })
          end

          def position_of(edit)
            Domain::KeyPosition.new(hand: edit.hand.to_sym, row: edit.row, col: edit.col)
          rescue InvalidValue => e
            raise InvalidChange.new('edit', "位置が正しくありません: #{e.message}")
          end

          def check_symbol!(name, symbols)
            unless name.match?(Domain::PositionMap::SYMBOL_FORMAT)
              raise InvalidChange.new('edit.to', "位置の名前は英数字と _ - だけで書いてください: #{name}")
            end
            raise InvalidChange.new('edit.to', "同じグループに同じ名前があります: #{name}") if symbols.include?(name)
          end

          def position_map_file
            Storage::ConfigFiles::EXTENSIONS.map { |ext| "#{Storage::ConfigFiles::POSITION_MAP}#{ext}" }
                                            .find { |file| reading.files[file] }
          end

          # 未使用のレイヤーのファイル（index のないもの）も書き換える（残すと位置の名前が position_map にないという警告になる）
          def rename_layer_keys(path, name)
            used = profile.layers.each_index.filter_map { |i| reading.repository.address("layers[#{i}]")&.first }
            unused = reading.unused.select { |file| file.kind == :layers }.map(&:file)
            (used + unused).each do |file|
              edit_file(file) { |text| YamlKeys.new(text).rename_key(path, name) }
            end
          end
        end
      end
    end
  end
end
