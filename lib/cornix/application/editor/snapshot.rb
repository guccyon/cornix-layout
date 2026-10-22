# frozen_string_literal: true

require_relative 'profile_reading'
require_relative 'key_values'
require_relative 'diagnostics'
require_relative 'inspect'
require_relative 'snapshot/items'

module Cornix
  module Application
    module Editor
      # 開いているプロファイルを読み、画面に描くものをまとめる（protocol.md の 5.2 の ProfileSnapshot）。
      #
      #   Snapshot.new(workbench).call('p1')
      #   #=> { profileId:, name:, dir:, status: "ok" | "invalid", files:, metadata:, positionMap:, layers:, settings:,
      #   #     references:, macros:, tapDances:, combos:, shortcuts:, diagnostics: }
      #
      # v0.2 で足したもの（protocol.md の 12.2）: macros / tapDances / combos / shortcuts（Snapshot::Items）、
      # positionMap の各位置の address（position_map.yaml の名前を書いている場所 [hand, group, 並びの位置]）、
      # レイヤーの descriptionAddress（["description"]。書いていなければ挿入の場所）
      #
      # 読んだファイルの版を workbench.versions(id) の「知っている版」にする（前の中身は置き換える）。
      # 構造検証で読めなければ status: "invalid" で、files と diagnostics のほかは空（metadata は {}）。
      # 読めない値（解析できないキーコード）だけなら status: "ok" で、その割り当ては書いてある表記のまま返し、diagnostics に構造の error と意味検証の結果を並べる。
      #
      # layers の keys は position_map のすべての位置（割り当てのない位置は value: nil）、encoders は左右の push / ccw / cw
      # （ファイルに書いていない操作は value: nil）。value の text はファイルに書いてある表記（YamlDocument#scalar）。
      # settings は data/qmk_settings.yaml のすべての設定（ファイルにない設定は value: nil）。
      # 設定の Address は名前の形（[group, name]）。ファイルが旧 decompile の QSID の番号の形（'7': 180）で書いていればその場所（['7']）
      class Snapshot
        ENCODER_SIDES = Domain::Layer::ENCODER_SIDES
        ENCODER_ACTIONS = Domain::EncoderBinding::ACTIONS

        def initialize(workbench, icons: Mapping::AppIconCatalog.default)
          @workbench = workbench
          @icons = icons
        end

        def call(id)
          opened = @workbench.fetch(id)
          env = opened.env
          reading = ProfileReading.read(env)
          versions = @workbench.versions(id)
          versions.replace(reading.files)
          head = { profileId: opened.id, name: opened.name, dir: opened.dir, status: reading.ok? ? 'ok' : 'invalid',
                   files: reading.files }
          diagnostics = Diagnostics.new(reading, env.capabilities).call
          body = reading.ok? ? unreadable_values(contents(env, reading), diagnostics) : empty_contents
          head.merge(body, diagnostics: diagnostics)
        end

        private

        # 読めない値（ProfileReading の説明。代わりに NoKey で読んだ割り当て）は、書いてある表記をそのまま図と欄に出す
        # （canonical と display.label を text にする。どれかは diagnostics の構造の error で分かる）
        def unreadable_values(body, diagnostics)
          unreadable = diagnostics.filter_map { |d| d[:address] if d[:source] == 'structure' }.to_set
          return body if unreadable.empty?

          patch = lambda do |node|
            case node
            when Array then node.map { |child| patch.call(child) }
            when Hash
              node = node.transform_values { |child| patch.call(child) }
              value = node[:value]
              if node[:address] && unreadable.include?(node[:address]) && value.is_a?(Hash) && value[:text]
                node = node.merge(value: value.merge(canonical: value[:text], display: { label: value[:text] }))
              end
              node
            else node
            end
          end
          patch.call(body)
        end

        def empty_contents
          { metadata: {}, positionMap: [], layers: [], settings: [],
            references: { layers: [], macros: [], tapDances: [], shortcuts: [] },
            macros: [], tapDances: [], combos: [], shortcuts: [] }
        end

        def contents(env, reading)
          profile = reading.profile
          values = KeyValues.new(env: env, profile: profile, icons: @icons)
          description = Inspect::Description.new(values: values, profile: profile, qmk: env.qmk)
          {
            metadata: profile.metadata.to_h,
            positionMap: position_map(profile.position_map, reading),
            layers: profile.layers.each_with_index.map { |layer, i| layer(layer, i, profile.position_map, reading, values) },
            settings: settings(env.settings_catalog, profile.settings, reading),
            references: references(profile, reading, values),
            **Items.new(reading: reading, values: values, description: description).to_h
          }
        end

        def position_map(map, reading)
          file = position_map_file(reading)
          map.positions.map do |pos|
            group, symbol = map.symbol(pos)
            hand_key = map.hand_key(pos)
            path = [hand_key, group, map.symbols(hand_key, group).index(symbol)]
            { hand: pos.hand.to_s, row: pos.row, col: pos.col, group: group, symbol: symbol,
              address: { file: file, path: path } }
          end
        end

        # position_map.yaml（.yml も。読めたプロファイルでは必ずある）
        def position_map_file(reading)
          Storage::ConfigFiles::EXTENSIONS.map { |ext| "#{Storage::ConfigFiles::POSITION_MAP}#{ext}" }
                                         .find { |rel| reading.files.key?(rel) }
        end

        def layer(layer, position, map, reading, values)
          file, = reading.repository.address("layers[#{position}]")
          doc = reading.document(file)
          keys = map.positions.map do |pos|
            group, symbol = map.symbol(pos)
            path = ['mapping', map.hand_key(pos), group, symbol]
            keycode = layer.key(pos)
            value = keycode && values.build(keycode, text: written(doc, path) || values.canonical(keycode),
                                                     note: layer.note(pos))
            { hand: pos.hand.to_s, row: pos.row, col: pos.col, address: { file: file, path: path }, value: value }
          end
          { index: layer.index, name: layer.name, description: layer.description, file: file,
            descriptionAddress: { file: file, path: ['description'] }, keys: keys,
            encoders: encoders(layer, file, doc, values) }
        end

        def encoders(layer, file, doc, values)
          ENCODER_SIDES.to_h do |side|
            binding = layer.encoder(side)
            actions = ENCODER_ACTIONS.to_h do |action|
              path = ['mapping', 'encoders', side.to_s, action.to_s]
              text = written(doc, path)
              value = text && values.build(binding.public_send(action), text: text, note: binding.note(action))
              [action, { address: { file: file, path: path }, value: value }]
            end
            [side, actions]
          end
        end

        # ファイルに書いてある表記（書いていない・空なら nil）
        def written(doc, path) = doc&.scalar(path)

        def settings(catalog, values, reading)
          file = reading.settings_file || ProfileReading::SETTINGS_FILE
          doc = reading.document(file)
          catalog.all.map do |definition|
            raw = values[definition.qsid]
            value = raw.nil? || !definition.boolean? ? raw : raw == 1
            { group: definition.group, name: definition.name, type: definition.type, value: value,
              default: definition.default, description: definition.description,
              address: { file: file, path: setting_path(doc, definition) } }
          end
        end

        def setting_path(doc, definition)
          named = [definition.group, definition.name]
          legacy = [definition.qsid.to_s]
          return legacy if doc && doc.range(named).nil? && doc.range(legacy)

          named
        end

        def references(profile, reading, values)
          shortcuts_doc = reading.shortcuts_file && reading.document(reading.shortcuts_file)
          {
            layers: profile.layers.map { |layer| { index: layer.index, name: layer.name } },
            macros: profile.macros.map { |m| { index: m.index, name: m.name, icon: values.macro_icon(m) } },
            tapDances: profile.tap_dances.map { |t| { index: t.index, name: t.name } },
            shortcuts: profile.shortcuts.entries.map do |name, keycode|
              { name: name, text: shortcuts_doc&.scalar(['shortcuts', name]) || values.plain(keycode) }
            end
          }
        end
      end
    end
  end
end
