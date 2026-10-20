# frozen_string_literal: true

require_relative 'profile_reading'
require_relative 'key_values'
require_relative 'unknown_context'

module Cornix
  module Application
    module Editor
      # キー入力欄の候補（protocol.md の 5.3 keycode/candidates）と、同梱のショートカットの木（5.4 keycode/shortcutTree）。
      #
      #   candidates = Candidates.new(workbench)
      #   candidates.call('p1', context: 'layerKey', query: 'Cmd', limit: 50)
      #   #=> { items: [{ insertText:, label:, detail:, category:, icon:, warning: }], typed: KeyValue | nil, truncated: }
      #   candidates.shortcut_tree
      #   #=> { apps: [{ name:, icon:, categories: [{ name:, items: [{ label:, insertText:, text:, macro: }] }] }] }
      #
      # 名前参照（マクロ・タップダンス・利用者のショートカット・レイヤーの名前）は保存済みのプロファイルから取る
      # （構造検証で読めなければ、同梱のショートカットとキーの表だけ）。並べ方は Mapping::CandidateCatalog。
      # 同梱のショートカットとアプリには Mapping::AppIconCatalog のアイコン、preset: のマクロの候補には元のアプリのアイコンを付ける。
      # 候補の nil の項目（detail / icon / warning）は省く。limit を省いたら DEFAULT_LIMIT、1 未満は 1。
      # typed は query をそのまま表記として読めたときの解釈（空や読めないときは nil）。
      # 知らない context は UnknownContext。shortcut_tree は同梱のデータだけから作るので、アイコンの表ごとに 1 回だけ作って持つ
      class Candidates
        DEFAULT_LIMIT = Mapping::CandidateCatalog::DEFAULT_LIMIT
        SHORTCUT_TREES = {}.compare_by_identity # アイコンの表 => shortcut_tree の結果
        private_constant :SHORTCUT_TREES

        def initialize(workbench, icons: Mapping::AppIconCatalog.default)
          @workbench = workbench
          @icons = icons
        end

        def call(id, context:, query:, limit: nil)
          env = @workbench.fetch(id).env
          UnknownContext.check!(context)
          catalog = catalog(env)
          reading = ProfileReading.read(env)
          values = KeyValues.new(env: env, profile: reading.profile, icons: @icons)
          result = catalog.search(query: query.to_s, context: context, references: values.references,
                                  layer_names: values.layer_names, limit: limit || DEFAULT_LIMIT)
          macro_icons = macro_icons(reading.profile, values)
          {
            items: result.items.map { |candidate| item(candidate, macro_icons) },
            typed: typed(values, query.to_s),
            truncated: result.truncated
          }
        end

        def shortcut_tree
          SHORTCUT_TREES[@icons] ||= { apps: catalog(Environment.new).shortcut_tree.map { |app| shortcut_app(app) } }.freeze
        end

        private

        def catalog(env)
          Mapping::CandidateCatalog.new(catalog: env.catalog, notation: env.notation, shortcut_catalog: env.shortcut_catalog,
                                        icon_for: ->(app_name) { @icons.icon(app_name) })
        end

        def item(candidate, macro_icons)
          icon = candidate.icon || (candidate.category == 'macro' ? macro_icons[candidate.insert_text] : nil)
          { insertText: candidate.insert_text, label: candidate.label, detail: candidate.detail,
            category: candidate.category, icon: icon, warning: candidate.warning }.compact
        end

        # preset: のマクロの候補の表記（Macro('名前')）→ 元のアプリのアイコン
        def macro_icons(profile, values)
          return {} unless profile

          profile.macros.each_with_object({}) do |macro, icons|
            icon = values.macro_icon(macro) or next
            icons[values.canonical(Domain::Keycode::MacroCall.new(index: macro.index))] = icon
          end
        end

        def typed(values, query)
          return nil if query.strip.empty?

          values.build(values.parse(query), text: query)
        rescue UnknownKeycode
          nil
        end

        def shortcut_app(app)
          categories = app[:categories].map do |category|
            items = category[:items].map do |entry|
              { label: entry[:label], insertText: entry[:insert_text], text: entry[:text], macro: entry[:macro] }.compact
            end
            { name: category[:name], items: items }
          end
          { name: app[:name], icon: app[:icon], categories: categories }
        end
      end
    end
  end
end
