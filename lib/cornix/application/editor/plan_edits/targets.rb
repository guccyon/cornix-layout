# frozen_string_literal: true

module Cornix
  module Application
    module Editor
      class PlanEdits
        # 変更の宛先にできる Address の表（protocol.md の 2 の Address。profile/open の結果に出てくる Address だけ）。
        # Snapshot と同じ読み方で、レイヤーのキー（position_map のすべての位置）・エンコーダの操作・QMK 設定の場所を並べる。
        #
        #   targets = Targets.new(reading, settings_catalog)
        #   target = targets.fetch('layers/0_base.yml', %w[mapping left_hand row0 tab])
        #   target.order     #=> YamlDocument#insert の order（{ 親の道筋 => キーの並び }）
        #   target.setting   #=> QMK 設定なら Mapping::QmkSettingCatalog::Definition、キーなら nil
        #
        # 構造検証で読めないプロファイル（reading.ok? が false）には宛先がない
        class Targets
          Target = Data.define(:file, :path, :order, :setting) do
            def setting? = !setting.nil?
          end

          LAYER_KEYS = Storage::Schema::LayerFile::KEYS
          HANDS = Storage::Schema::LayerFile::HANDS
          GROUPS = Storage::Schema::LayerFile::GROUPS
          SIDES = Storage::Schema::LayerFile::SIDES
          ACTIONS = Storage::Schema::LayerFile::ACTIONS

          def initialize(reading, settings_catalog)
            @table = {}
            return unless reading.ok?

            add_layers(reading)
            add_settings(reading, settings_catalog)
          end

          # file と path（JSON の道筋。文字列か整数）の宛先。指せなければ nil
          def fetch(file, path) = @table[[file, path]]

          private

          def add(file, path, order, setting = nil)
            @table[[file, path]] = Target.new(file: file, path: path.freeze, order: order, setting: setting)
          end

          def add_layers(reading)
            map = reading.profile.position_map
            reading.profile.layers.each_index do |i|
              file, = reading.repository.address("layers[#{i}]")
              next unless file

              map.positions.each do |pos|
                hand = map.hand_key(pos)
                group, symbol = map.symbol(pos)
                order = layer_order.merge(['mapping', hand, group] => map.symbols(hand, group))
                add(file, ['mapping', hand, group, symbol], order)
              end
              SIDES.each do |side|
                ACTIONS.each { |action| add(file, ['mapping', 'encoders', side, action], encoder_order) }
              end
            end
          end

          # レイヤーのファイルの見出しの並び（ConfigWriter が書く順）
          def layer_order
            @layer_order ||= { [] => LAYER_KEYS, ['mapping'] => HANDS + ['encoders'] }
                             .merge(HANDS.to_h { |hand| [['mapping', hand], GROUPS] }).freeze
          end

          def encoder_order
            @encoder_order ||= layer_order.merge(['mapping', 'encoders'] => SIDES)
                                          .merge(SIDES.to_h { |side| [['mapping', 'encoders', side], ACTIONS] }).freeze
          end

          # QMK 設定の Address は Snapshot と同じく名前の形（[group, name]）。
          # ファイルが旧 decompile の QSID の番号の形（'7': 180）で書いていて名前の形がなければ、その場所（['7']）
          def add_settings(reading, catalog)
            file = reading.settings_file || ProfileReading::SETTINGS_FILE
            doc = reading.document(file)
            groups = (Storage::Schema::SettingsFile::GROUP_ORDER + catalog.all.map(&:group)).uniq
            names = catalog.all.group_by(&:group).transform_values { |list| list.map(&:name) }
            catalog.all.each do |definition|
              named = [definition.group, definition.name]
              legacy = [definition.qsid.to_s]
              path = doc && doc.range(named).nil? && doc.range(legacy) ? legacy : named
              order = { [] => groups, [definition.group] => names.fetch(definition.group) }
              add(file, path, order, definition)
            end
          end
        end
      end
    end
  end
end
