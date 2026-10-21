# frozen_string_literal: true

require_relative 'operation'

module Cornix
  module Application
    module Editor
      class ItemEdits
        # 項目を足す（protocol.md の 12.5 の create）。
        #
        # マクロ・タップダンス・コンボ: 空いているいちばん小さい番号で、<番号>_<slug>.<拡張子> のファイルを作る。
        # 拡張子はそのディレクトリでいちばん多いもの（同じ数なら .yaml、ファイルがなければ .yaml）。
        # 中身は Schema::*File.write と同じ項目の並びの最小のもの:
        #   マクロ      index・name・description: ''・sequence（action: tap、keys: [KC_NO] の手順 1 つ）か preset
        #   タップダンス index・name・description: ''（動作なし）
        #   コンボ      index・name・description: ''・trigger_keys: [KC_NO, KC_NO]・output_key: KC_NO
        # レイヤー（v0.4。issue #84）: 選んだ番号（省けば空いているいちばん小さい番号）で、layers/<番号>_<名前>.<拡張子> のファイルを作る
        #   （名前の部分は Storage::ConfigFiles.item_path と同じ。decompile が書く名前とそろえる）。
        #   中身は Schema::LayerFile が受け付ける最小のもの（name・description: ''・index・mapping の両手の空のグループ。エンコーダは書かない）
        # ショートカット: shortcuts.yaml の shortcuts: の末尾に「名前: 値」の行を足す（ファイルがなければ作る）
        class Create < Operation
          NO_KEY = 'KC_NO'

          private

          def run(edit)
            return create_shortcut(edit) if edit.kind == 'shortcut'

            kind = kind_of(edit)
            check_name!(edit.name, 'edit.name', kind.items(profile).map(&:name))
            check_preset!(edit.preset) if edit.preset
            index = edit.index.nil? ? free_index(kind) : chosen_index(kind, edit.index)
            changeset.create(new_file(kind, index, edit.name), Storage::YamlFile.dump(content(kind, index, edit)))
            outcome
          end

          def check_preset!(name)
            return if env.shortcut_catalog.preset_names.include?(name)

            raise InvalidChange.new('edit.preset', "プリセット「#{name}」は同梱のショートカット（data/shortcuts/）にありません")
          end

          def free_index(kind)
            limit = kind.limit(env.capabilities)
            used = kind.items(profile).map(&:index)
            (0...limit).find { |i| !used.include?(i) } or
              raise InvalidChange.new('edit', "#{kind.label}は #{limit} 件までです（空いている番号がありません）")
          end

          def chosen_index(kind, index)
            limit = kind.limit(env.capabilities)
            unless (0...limit).cover?(index)
              raise InvalidChange.new('edit.index', "#{kind.label}の番号は 0〜#{limit - 1} です: #{index}")
            end
            if kind.items(profile).any? { |item| item.index == index }
              raise InvalidChange.new('edit.index', "#{kind.label} #{index} はもうあります")
            end

            index
          end

          def new_file(kind, index, name)
            base =
              if kind.name == 'layer'
                Storage::ConfigFiles.item_path(kind.files, index, name).delete_suffix(Storage::ConfigFiles::WRITE_EXTENSION)
              else
                "#{kind.directory}/#{index.to_s.rjust(kind.digits, '0')}_#{slug(kind, name)}"
              end
            ext = extension(kind.directory)
            file = "#{base}#{ext}"
            n = 1
            file = "#{base}_#{n += 1}#{ext}" while taken?(file)
            file
          end

          # 同じ名前（拡張子違いも）のファイルがある
          def taken?(file)
            stem = file.delete_suffix(File.extname(file))
            Storage::ConfigFiles::EXTENSIONS.any? { |ext| changeset.exist?("#{stem}#{ext}") }
          end

          # いちばん多い拡張子（同じ数なら .yaml。なければ .yaml）
          def extension(directory)
            default = Storage::ConfigFiles::WRITE_EXTENSION
            counts = reading.files.keys.select { |file| File.dirname(file) == directory }.map { |file| File.extname(file) }.tally
            max = counts.values.max
            return default if max.nil? || counts[default] == max

            counts.key(max)
          end

          def content(kind, index, edit)
            return layer_content(index, edit.name) if kind.name == 'layer'

            head = { 'index' => index, 'name' => edit.name, 'description' => '' }
            case kind.name
            when 'macro'
              edit.preset ? head.merge('preset' => edit.preset) : head.merge('sequence' => [{ 'action' => 'tap', 'keys' => [NO_KEY] }])
            when 'combo' then head.merge('trigger_keys' => [NO_KEY, NO_KEY], 'output_key' => NO_KEY)
            else head
            end
          end

          def layer_content(index, name)
            # 手ごとに別の Hash にする（同じものだと YAML のアンカー &1 / *1 で書かれる）
            groups = -> { Storage::Schema::LayerFile::GROUPS.to_h { |group| [group, {}] } }
            { 'name' => name, 'description' => '', 'index' => index,
              'mapping' => Storage::Schema::LayerFile::HANDS.to_h { |hand| [hand, groups.call] } }
          end

          def create_shortcut(edit)
            check_name!(edit.name, 'edit.name', shortcut_names)
            raise InvalidChange.new('edit.value', 'ショートカットの値が空です') if edit.value.to_s.strip.empty?

            file = reading.shortcuts_file || Storage::ConfigFiles.single_path(Storage::ConfigFiles::SHORTCUTS)
            edit_file(file) { |text| Storage::YamlDocument.parse(text).insert(['shortcuts', edit.name], edit.value) }
            outcome
          end
        end
      end
    end
  end
end
