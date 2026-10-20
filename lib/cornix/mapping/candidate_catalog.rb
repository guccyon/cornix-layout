# frozen_string_literal: true

module Cornix
  module Mapping
    # キー入力欄の候補の表と並べ方（VS Code 拡張の keycode/candidates と keycode/shortcutTree。
    # docs/vscode-extension/protocol.md の 5.3・5.4、spec.md の「入力と補完」）。
    #
    #   candidates = CandidateCatalog.new(catalog:, notation:, shortcut_catalog:, categories: CandidateCatalog.default_categories,
    #                                     icon_for: ->(app_name) { nil })
    #   candidates.search(query:, context: 'layerKey', references:, layer_names: { 1 => 'Symbols' }, limit: 50)
    #     #=> Result(items: [Candidate], truncated:)
    #   candidates.shortcut_tree #=> [{ name:, icon:, categories: [{ name:, items: [{ label:, insert_text:, text:, macro: }] }] }]
    #
    # 候補の元
    #   キー        data/keycodes.yaml と data/aliases.yaml の名前のある値（dangerous_keycodes.yaml の値は除く）。分類は data/keycode_categories.yaml
    #   layer       layer_names のレイヤーごとの MO / TG / TO / OSL / TT / DF / PDF。detail にレイヤーの名前
    #   macro / tapDance / shortcut  references の名前（Macro('名前') / TapDance('名前') / Shortcut('名前')）
    #   presetShortcut  data/shortcuts/ の 1 シーケンスの定義（Shortcut('アプリ:カテゴリ:ラベル')）。macro: の定義は出さない
    #   raw         query が 0x で始まり 16 進として読めるときだけ、その値（先頭に出す）。insert_text は references 付きの
    #               decompile の正規形（名前付きのマクロ 0 があれば 0x7700 → Macro('名前')）
    #
    # キーの表の候補は references によらない表記（選んだ名前をそのまま書く）。利用者のショートカットと同じ値のキー（"!" など）を
    # 選んでも Shortcut('名前') にはしない（decompile ならそう書くが、選んだ表記を残す。spec.md の「手で打った表記は残す」と同じ扱い）
    #
    # 並べ方: 対応していないキー（unsupported_keycodes.yaml。warning に理由）を最後に、その前は
    # 「完全一致 → 前方一致 → 部分一致」（大文字小文字は区別しない）、同じなら context の上に出すもの（keycode_categories.yaml の contexts。上に出すものどうしは書いた順）、
    # 同じなら分類の順（keycode_categories.yaml の order のあとに layer, macro, tapDance, shortcut, presetShortcut）と表の順。
    # query が空なら全部が一致したものとして並べる。
    #
    # 場面（context）ごとの扱い（protocol.md の 12.4）
    #   exclude.categories  その分類の候補を出さない（all: true なら出す）
    #   prefer.baseLayer    base_codes（ベースレイヤーに割り当ててある 16bit 値）と同じ値の候補を上に出す
    #   exclude:            その 16bit 値と同じ値の候補を出さない（タップダンスの動作の欄でそのタップダンス自身を除くなど）
    #   format_references:  候補の表記（insert_text）を作る名前参照。マクロの手順のキーは名前参照を読まないので
    #                       References::NONE を渡すと、マクロ・タップダンスの候補は M0 / TD(4) の形になる（label は名前のまま）
    class CandidateCatalog
      Candidate = Data.define(:insert_text, :label, :detail, :category, :icon, :warning)
      Result = Data.define(:items, :truncated)

      # 表から作る分類のあとに並べる分類
      GROUPS = %w[layer macro tapDance shortcut presetShortcut].freeze
      # 候補に出すレイヤー操作の並び（よく使う順。KeyDisplay::LAYER_OPS は表記の対応で、並びは意図して別）
      LAYER_OPS = %i[momentary toggle to one_shot tap_toggle default persistent_default].freeze
      DETAIL_ALIASES = 3
      RAW = /\A0x(\h{1,4})\z/i
      RAW_PREFIX = /\A0x/i
      DETAIL_SEPARATOR = ' · '
      PATH_SEPARATOR = ' › '
      DEFAULT_LIMIT = 50

      # 候補 1 つと、当てる文字（小文字にしたもの）・並べるための値。
      # key_name はキーの表の候補の keycodes.yaml の name、shortcut は同梱のショートカットの名前
      # code はその候補の 16bit 値（exclude と base_codes で比べる）
      Entry = Data.define(:candidate, :terms, :position, :key_name, :shortcut, :unsupported, :code)
      private_constant :Entry

      def self.default_categories = @default_categories ||= Categories.load

      def initialize(catalog: KeycodeCatalog.default, notation: KeycodeNotation.new(catalog: catalog),
                     shortcut_catalog: ShortcutCatalog.default, categories: self.class.default_categories,
                     icon_for: ->(_app_name) {})
        @catalog = catalog
        @notation = notation
        @codec = notation.codec
        @shortcut_catalog = shortcut_catalog
        @categories = categories
        @icon_for = icon_for
        @display = KeyDisplay.new(catalog: catalog, notation: notation)
        @group_order = (categories.order + GROUPS).each_with_index.to_h
        @unsupported = catalog.unsupported_keycodes.to_h { |code, message| [code, unsupported_reason(code, message)] }
        check_category_names!
        @key_entries = build_key_entries
        @preset_entries = build_preset_entries
      end

      # context の名前（data/keycode_categories.yaml の contexts）
      def contexts = @categories.contexts

      # references が Shortcut(...) を使えない場面（shortcuts_available? が false。既定の NONE も）なら、
      # 選んでも読めないので shortcut / presetShortcut の候補は出さない。limit は 1 未満なら 1 にする
      def search(query:, context:, references: References::NONE, layer_names: {}, limit: DEFAULT_LIMIT, all: false,
                 exclude: nil, base_codes: [], format_references: references)
        raise ArgumentError, "知らない context です: #{context.inspect}" unless @categories.context?(context)

        limit = [limit.to_i, 1].max

        query = query.to_s.strip
        needle = query.downcase
        base = @categories.prefer_base_layer?(context) ? base_codes.to_set : Set.new
        entries = @key_entries + reference_entries(references, layer_names, format_references) + preset_entries(references)
        ranked = entries.filter_map do |entry|
          next unless shown?(entry.candidate.category, entry.code, context, all, exclude)

          rank = match_rank(entry.terms, needle)
          rank && [entry, sort_key(entry, rank, context, base)]
        end
        items = ranked.sort_by(&:last).map { |entry, _| entry.candidate }
        items.unshift(*raw_candidates(query, format_references, context, all, exclude))
        Result.new(items: items.first(limit).freeze, truncated: items.size > limit)
      end

      def shortcut_tree
        @shortcut_tree ||= build_shortcut_tree.freeze
      end

      private

      # ---- 並べ方

      # 0: 完全一致、1: 前方一致、2: 部分一致、nil: 当たらない
      def match_rank(terms, needle)
        return 0 if needle.empty?

        terms.filter_map do |term|
          if term == needle then 0
          elsif term.start_with?(needle) then 1
          elsif term.include?(needle) then 2
          end
        end.min
      end

      def sort_key(entry, rank, context, base)
        category = entry.candidate.category
        prefer = @categories.prefer_rank(context, category, entry.key_name) || (base.include?(entry.code) ? 0 : nil)
        [entry.unsupported ? 1 : 0, rank, prefer || Float::INFINITY, @group_order.fetch(category), entry.position]
      end

      def shown?(category, code, context, all, exclude)
        return false if !exclude.nil? && code == exclude

        all || !@categories.exclude?(context, category)
      end

      # ---- キーの表

      def check_category_names!
        unknown = @categories.names.reject { |name| @catalog.code_for_name(name) && @catalog.name(@catalog.code_for_name(name)) == name }
        return if unknown.empty?

        raise ConfigError.new("keycodes.yaml の name にないキーです: #{unknown.join(', ')}", path: Categories::PATH)
      end

      def build_key_entries
        names_by_code = @catalog.names.group_by { |name| @catalog.lookup(name) }
        entries = names_by_code.keys.sort.filter_map do |code|
          next if @catalog.dangerous?(code)

          key_entry(code, names_by_code.fetch(code))
        end
        entries.freeze
      end

      def key_entry(code, names)
        keycode = @codec.decode(code)
        text = @notation.format(keycode)
        name = @catalog.name(code)
        category = @categories.category(name, section(code))
        aliases = @catalog.aliases_for(code)
        qmk_names = names - aliases
        detail = ((aliases - [text]).first(DETAIL_ALIASES) + [name || qmk_names.first]).compact.uniq - [text]
        terms = (names + [@display.display(keycode)[:label]]).reject(&:empty?)
        position = [@categories.position(name) || Float::INFINITY, code]
        Entry.new(candidate: Candidate.new(insert_text: text, label: text, detail: join(detail), category: category,
                                           icon: nil, warning: @unsupported[code]),
                  terms: downcase(terms), position: position, key_name: name, shortcut: nil,
                  unsupported: @unsupported.key?(code), code: code)
      end

      def section(code)
        if code <= 0x0001 then :special
        elsif @catalog.basic?(code) then :basic
        elsif @catalog.quantum?(code) then :quantum
        else :modified
        end
      end

      # "QK_REPEAT_KEY: Cornix は Repeat Key に対応していません" → 理由だけ
      # KeycodeCatalog#unsupported_keycodes の文の形（"名前: 理由"、名前がなければ "0xHHHH: 理由"）に頼っている。
      # 形が変わったら spec（範囲内のすべての値で data/unsupported_keycodes.yaml の reason と一致すること）が落ちる
      def unsupported_reason(code, message)
        message.delete_prefix("#{@catalog.name(code) || hex(code)}: ")
      end

      # ---- プロファイルから作る候補（レイヤー・マクロ・タップダンス・利用者のショートカット）

      def reference_entries(references, layer_names, format_references)
        layer_entries(layer_names) + macro_entries(references, format_references) +
          tap_dance_entries(references, format_references) + shortcut_entries(references)
      end

      def layer_entries(layer_names)
        layer_names.keys.sort.flat_map do |index|
          name = layer_names[index]
          LAYER_OPS.each_with_index.map do |op, i|
            keycode = Domain::Keycode::LayerAction.new(op: op, layer: Domain::LayerRef.new(index: index))
            text = @notation.format(keycode)
            reference_entry(text, text, name, 'layer', [i, index], [text, name, "L#{index}"], keycode)
          end
        end
      end

      def macro_entries(references, format_references)
        references.macro_names.map do |name|
          index = references.macro_index(name)
          keycode = Domain::Keycode::MacroCall.new(index: index)
          text = @notation.format(keycode, references: format_references)
          reference_entry(text, name, "M#{index}", 'macro', [index], [name, text, "M#{index}"], keycode)
        end
      end

      def tap_dance_entries(references, format_references)
        references.tap_dance_names.map do |name|
          index = references.tap_dance_index(name)
          keycode = Domain::Keycode::TapDanceCall.new(index: index)
          text = @notation.format(keycode, references: format_references)
          reference_entry(text, name, "TD(#{index})", 'tapDance', [index], [name, text, "TD(#{index})"], keycode)
        end
      end

      def shortcut_entries(references)
        return [] unless references.shortcuts_available?

        references.shortcut_names.each_with_index.map do |name, i|
          keycode = references.shortcut(name)
          reference_entry(shortcut_text(name), name, @notation.format(keycode), 'shortcut', [i], [name], keycode)
        end
      end

      def reference_entry(text, label, detail, category, position, terms, keycode)
        Entry.new(candidate: Candidate.new(insert_text: text, label: label, detail: detail, category: category,
                                           icon: nil, warning: nil),
                  terms: downcase(terms.compact), position: position, key_name: nil, shortcut: nil, unsupported: false,
                  code: @codec.encode(keycode))
      end

      # ---- 同梱のショートカット

      # 利用者のショートカットに同じ名前があれば、そちらが使われるので同梱の候補は出さない
      def preset_entries(references)
        return [] unless references.shortcuts_available?

        user = references.shortcut_names.to_set
        return @preset_entries if user.empty?

        @preset_entries.reject { |entry| user.include?(entry.shortcut) }
      end

      def build_preset_entries
        @shortcut_catalog.texts.each_with_index.map do |(name, text), i|
          app, category, label = split(name)
          Entry.new(candidate: Candidate.new(insert_text: shortcut_text(name), label: label,
                                             detail: "#{app}#{PATH_SEPARATOR}#{category}#{DETAIL_SEPARATOR}#{text}",
                                             category: 'presetShortcut', icon: @icon_for.call(app), warning: nil),
                    terms: downcase([label, app, name]), position: [i], key_name: nil, shortcut: name,
                    unsupported: false, code: preset_code(text))
        end.freeze
      end

      # 同梱のショートカットの表記の 16bit 値（読めなければ nil。読めない定義は ShortcutCatalog#library が知らせる）
      def preset_code(text)
        @codec.encode(@notation.parse(text))
      rescue UnknownKeycode
        nil
      end

      def build_shortcut_tree
        apps = {}
        @shortcut_catalog.texts.each do |name, text|
          app, category, label = split(name)
          tree_items(apps, app, category) << { label: label, insert_text: shortcut_text(name), text: text, macro: false }
        end
        @shortcut_catalog.macro_names.each do |name|
          app, category, label = split(name)
          tree_items(apps, app, category) << { label: label, insert_text: name, text: nil, macro: true }
        end
        apps.map do |app, categories|
          { name: app, icon: @icon_for.call(app),
            categories: categories.map { |category, items| { name: category, items: items.freeze } }.freeze }
        end
      end

      def tree_items(apps, app, category)
        (apps[app] ||= {})[category] ||= []
      end

      # "アプリ:カテゴリ:ラベル" → [アプリ, カテゴリ, ラベル]。2 段の名前ならカテゴリは nil
      def split(name)
        parts = name.split(ShortcutCatalog::SEPARATOR)
        [parts.first, parts[1...-1].join(ShortcutCatalog::SEPARATOR).then { |c| c.empty? ? nil : c }, parts.last]
      end

      # ---- 直接の値

      def raw_candidates(query, references, context, all, exclude)
        return [] unless query.match?(RAW_PREFIX)

        match = query.match(RAW) or return []
        code = match[1].to_i(16)
        return [] if @catalog.dangerous?(code) || !shown?('raw', code, context, all, exclude)

        keycode = @codec.decode(code)
        text = @notation.format(keycode, references: references)
        label = hex(code)
        [Candidate.new(insert_text: text, label: label, detail: text == label ? nil : text, category: 'raw', icon: nil,
                       warning: @unsupported[code])]
      end

      # ---- 文字

      # Shortcut('名前')。' を含む名前は "..." で囲む（KeycodeNotation::Formatter と同じ規則）
      def shortcut_text(name)
        quoted = if !name.include?("'") then "'#{name}'"
                 elsif !name.include?('"') then "\"#{name}\""
                 else "'#{name.gsub("'", "\\\\'")}'"
                 end
        "Shortcut(#{quoted})"
      end

      def join(parts) = parts.empty? ? nil : parts.join(DETAIL_SEPARATOR)

      def downcase(terms) = terms.map(&:downcase).uniq.freeze

      def hex(code) = ::Kernel.format('0x%04X', code)
    end
  end
end
