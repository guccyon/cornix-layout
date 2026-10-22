# frozen_string_literal: true

module Cornix
  module Application
    module Editor
      class PlanEdits
        # 変更の宛先にできる Address の規則（protocol.md の 2 の Address と 12.3）。設定ファイルの種類ごとに、書ける場所と
        # そこでできる操作（op）・値の型・注記を書けるかを決める。名前（name）と番号（index）は宛先にしない（12.2）。
        #
        #   targets = Targets.new(reading, settings_catalog)
        #   target = targets.fetch('layers/0_base.yml', %w[mapping left_hand row0 tab])
        #   target.ops       #=> [:set, :remove]（できる操作）
        #   target.type      #=> 値の型（:key 表記の文字列、:string、:integer、:setting QMK 設定、:step マクロの手順。:remove だけなら nil）
        #   target.note      #=> 注記（field: "note"）を書けるか
        #   target.check     #=> 当てる直前の中身で確かめること（並びの位置など。Draft#check_state! が見る）
        #   target.order     #=> YamlDocument#insert の order（{ 親の道筋 => キーの並び } か、兄弟のキーの並び）
        #   target.setting   #=> QMK 設定なら Mapping::QmkSettingCatalog::Definition、ほかは nil
        #
        # レイヤーのキー（position_map のすべての位置）・エンコーダの操作・QMK 設定は表にし、マクロ・タップダンス・コンボ・
        # ショートカットは道筋の形で決める（並びの位置は前の変更で変わるので、ここでは形だけを見て、位置は当てる直前に確かめる）。
        # 宛先にできるのは、読み込んだ（いまディスクにある）設定ファイルの中だけ（ないファイルは指せない。QMK 設定のファイルは除く）。
        # 構造検証で読めないプロファイル（reading.ok? が false）には宛先がない
        class Targets
          Target = Data.define(:file, :path, :order, :setting, :type, :ops, :note, :check) do
            def initialize(file:, path:, order: [], setting: nil, type: :key, ops: %i[set], note: false, check: nil)
              super(file: file, path: path.freeze, order: order, setting: setting, type: type, ops: ops, note: note, check: check)
            end

            def setting? = !setting.nil?
          end

          LAYER_KEYS = Storage::Schema::LayerFile::KEYS
          HANDS = Storage::Schema::LayerFile::HANDS
          GROUPS = Storage::Schema::LayerFile::GROUPS
          SIDES = Storage::Schema::LayerFile::SIDES
          ACTIONS = Storage::Schema::LayerFile::ACTIONS
          TAP_DANCE_ACTIONS = Storage::Schema::TapDanceFile::ACTIONS

          # 項目のファイルの上の階層のキーの並び（Schema::*File.write の順。足すときの場所）
          MACRO_ORDER = %w[index name description enabled preset sequence].freeze
          STEP_ORDER = %w[action keys duration content].freeze
          TAP_DANCE_ORDER = (%w[index name description enabled actions] + TAP_DANCE_ACTIONS + %w[tapping_term]).freeze
          COMBO_ORDER = %w[index name description enabled trigger_keys output_key].freeze

          EDIT = %i[set remove].freeze
          LIST = %i[insert move].freeze

          def initialize(reading, settings_catalog)
            @table = {}
            @items = {}
            return unless reading.ok?

            add_layers(reading)
            add_settings(reading, settings_catalog)
            add_items(reading)
          end

          # file と path（JSON の道筋。文字列か整数）の宛先。指せなければ nil
          def fetch(file, path)
            @table[[file, path]] || item_target(file, path)
          end

          private

          def add(file, path, order, setting = nil, **options)
            @table[[file, path]] = Target.new(file: file, path: path, order: order, setting: setting, **options)
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
                add(file, ['mapping', hand, group, symbol], order, ops: EDIT, note: true)
              end
              SIDES.each do |side|
                ACTIONS.each { |action| add(file, ['mapping', 'encoders', side, action], encoder_order, ops: EDIT, note: true) }
              end
              add(file, ['description'], LAYER_KEYS, type: :string, ops: EDIT)
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
              add(file, path, order, definition, type: :setting)
            end
          end

          # ---- マクロ・タップダンス・コンボ・ショートカット ----

          # ファイル => [種類, 読んだ中身]。未使用のファイル（index のないもの）も宛先にする（中身の書き換えは別のファイルに及ばない。
          # 未使用の項目を画面で編集するのは #105）
          def add_items(reading)
            reading.files.each_key do |file|
              kind = %i[macros tap_dances combos].find { |k| Storage::ConfigFiles.kind_file?(file, k) }
              @items[file] = [kind, reading.data(file)] if kind
            end
            shortcuts = reading.shortcuts_file
            @items[shortcuts] = [:shortcuts, reading.data(shortcuts)] if shortcuts
          end

          def item_target(file, path)
            kind, data = @items[file]
            return nil unless kind && data.is_a?(Hash)

            options = send(:"#{kind}_target", path, data) or return nil
            Target.new(file: file, path: path, **options)
          end

          def description_target(order) = { type: :string, ops: EDIT, order: order }

          def macros_target(path, data)
            return { type: :string, ops: %i[set] } if path == ['preset'] && data.key?('preset')
            return description_target(MACRO_ORDER) if path == ['description']
            return nil if data.key?('preset')

            case path
            in ['sequence'] then { type: :step, ops: LIST, check: :list }
            in ['sequence', Integer] then { type: nil, ops: %i[remove], check: :element }
            in ['sequence', Integer, 'keys'] then { ops: EDIT + LIST, check: :step_keys }
            in ['sequence', Integer, 'keys', Integer] then { ops: EDIT, check: :element }
            in ['sequence', Integer, 'duration'] then { type: :integer, order: STEP_ORDER, check: :step_delay }
            in ['sequence', Integer, 'content'] then { type: :string, order: STEP_ORDER, check: :step_text }
            else nil
            end
          end

          # 動作の Address は、ファイルが上の階層に書いていれば ["on_tap"]、ほかは actions: の下（protocol.md の 12.2）
          def tap_dances_target(path, data)
            return description_target(TAP_DANCE_ORDER) if path == ['description']
            return { type: :integer, ops: EDIT, order: TAP_DANCE_ORDER } if path == ['tapping_term']

            prefix = TAP_DANCE_ACTIONS.any? { |a| data.key?(a) } ? [] : ['actions']
            return nil unless path.size == prefix.size + 1 && path[0...-1] == prefix && TAP_DANCE_ACTIONS.include?(path.last)

            { ops: EDIT, note: true, order: { [] => TAP_DANCE_ORDER, ['actions'] => TAP_DANCE_ACTIONS } }
          end

          def combos_target(path, data)
            return description_target(COMBO_ORDER) if path == ['description']
            return { ops: %i[set], note: true, order: COMBO_ORDER } if path == ['output_key'] && data.key?('output_key')

            case path
            in ['trigger_keys'] then { ops: LIST, check: :list }
            in ['trigger_keys', Integer] then { ops: EDIT, check: :element }
            else nil
            end
          end

          # 名前の Address（["shortcuts", 名前]）は、いま書いてある名前だけ。足す・消すは profile/planItemEdit
          def shortcuts_target(path, data)
            entries = data['shortcuts']
            return nil unless path.size == 2 && path[0] == 'shortcuts' && entries.is_a?(Hash) && entries.key?(path[1])

            { ops: %i[set] }
          end
        end
      end
    end
  end
end
