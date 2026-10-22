# frozen_string_literal: true

module Cornix
  module Application
    module Editor
      # 実機との差分（Planning::Change の列）を、拡張に渡す DeviceChange の Hash（protocol.md の 14.2）にする。
      #
      #   DeviceChanges.new(env, profile: profile).call(plan.changes)
      #   #=> [{ kind: "key", layer: 0, key: { hand: "left", row: 0, col: 1 }, position: "q",
      #          device: "KC_A", profile: "KC_Q", text: "レイヤー0 (0,1): KC_A → KC_Q" }, ...]
      #
      # - キー（SetKeycode）: マトリクスの座標を Domain::PositionMap で論理位置（key）と記号（position）に直す。
      #   エンコーダのプッシュの位置は kind "encoder"（direction "push"）。どちらでもない位置は kind "other"
      # - エンコーダ（SetEncoder）: index 0 が左、1 が右（ProfileMapper と同じ）。ほかの番号は kind "other"
      # - マクロ（ReplaceMacros）: 変わる番号ごとに 1 件にする（index と、プロファイルにあれば name）
      # - タップダンス・コンボ: index と、プロファイルにあれば name。設定: name に設定の名前（QmkSettingCatalog。なければ省く）
      # device / profile は変更の from / to の表記、text は 1 行の説明（どちらも Device::ChangeDescriber。CLI と同じ文）。
      # 並びは渡した順（Planning::Plan#changes の順。マクロは番号の順に展開する）。
      #
      # profile（Domain::Profile。省略可）は名前と位置の表に使う。なければ位置の表は設定ディレクトリの position_map
      # （読めなければテンプレート）から読み、名前は省く
      class DeviceChanges
        ENCODER_SIDES = Domain::PositionMap::ENCODER_SIDES

        def initialize(env, profile: nil)
          @env = env
          @profile = profile
        end

        def call(changes) = changes.flat_map { |change| convert(change) }

        private

        def describer = @env.describer

        def convert(change)
          case change
          when Planning::Change::SetKeycode then [entry(change, key_location(change))]
          when Planning::Change::SetEncoder then [entry(change, encoder_location(change))]
          when Planning::Change::ReplaceMacros then macro_entries(change)
          when Planning::Change::SetTapDance
            [entry(change, named(kind: 'tapDance', index: change.index, name: @profile&.tap_dance(change.index)&.name))]
          when Planning::Change::SetCombo
            [entry(change, named(kind: 'combo', index: change.index, name: @profile&.combo(change.index)&.name))]
          when Planning::Change::SetSetting
            [entry(change, named(kind: 'setting', name: @env.settings_catalog.fetch(change.qsid)&.name))]
          else [entry(change, { kind: 'other' })]
          end
        end

        def entry(change, location)
          location.merge(device: describer.value(change, change.from), profile: describer.value(change, change.to),
                         text: describer.format_change(change))
        end

        def named(kind:, index: nil, name: nil) = { kind: kind, index: index, name: name }.compact

        def key_location(change)
          position = position_map.position_at(change.row, change.col)
          if position
            _, symbol = position_map.symbol(position)
            return { kind: 'key', layer: change.layer, key: { hand: position.hand.to_s, row: position.row, col: position.col },
                     position: symbol }
          end
          side = ENCODER_SIDES.find { |s| position_map.encoder_push_matrix(s) == [change.row, change.col] }
          return { kind: 'encoder', layer: change.layer, encoder: { side: side.to_s, direction: 'push' } } if side

          { kind: 'other', layer: change.layer }
        end

        def encoder_location(change)
          side = ENCODER_SIDES[change.index]
          return { kind: 'other', layer: change.layer } if side.nil?

          { kind: 'encoder', layer: change.layer, encoder: { side: side.to_s, direction: change.clockwise ? 'cw' : 'ccw' } }
        end

        # 番号ごとに、その番号だけを変える ReplaceMacros として説明する
        def macro_entries(change)
          change.indexes.map do |index|
            entry(change.with(indexes: [index]), named(kind: 'macro', index: index, name: @profile&.macro(index)&.name))
          end
        end

        def position_map
          @position_map ||= @profile&.position_map || read_position_map
        end

        def read_position_map
          path = @env.repository.position_map_path
          Storage::ConfigRepository.read_position_map(path || @env.position_map_template)
        rescue Storage::InvalidConfig
          Storage::ConfigRepository.read_position_map(@env.position_map_template)
        end
      end
    end
  end
end
