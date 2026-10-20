# frozen_string_literal: true

require 'yaml'
require_relative '../candidate_catalog'

module Cornix
  module Mapping
    class CandidateCatalog
      # 候補の分類と場面ごとに上に出すもの（data/keycode_categories.yaml）。形の誤りは ConfigError。
      #
      #   categories.category(name, section)   キーの分類（name は keycodes.yaml の name か nil、section は :special / :basic / :quantum / :modified）
      #   categories.position(name)            同じ分類の中での並び（categories に書いた順。書いていなければ nil）
      #   categories.order                     分類の並び
      #   categories.contexts                  場面の名前
      #   categories.prefer?(context, category, name)  その場面で上に出すものか（分類かキーの名前で）
      #   categories.prefer_base_layer?(context)       ベースレイヤーに割り当ててある値を上に出す場面か
      #   categories.exclude?(context, category)       その場面で出さない分類か（params の all: true なら出す）
      #
      # contexts の分類には order の分類のほか、表ではなくプロファイルと入力から作る分類（EXTRA_CATEGORIES）も書ける
      class Categories
        PATH = File.join(Cornix::DATA_DIR, 'keycode_categories.yaml')
        SECTIONS = %i[special basic quantum modified].freeze
        EXTRA_CATEGORIES = %w[layer macro tapDance shortcut presetShortcut raw].freeze
        CONTEXT_KEYS = %w[prefer exclude].freeze
        PREFER_KEYS = %w[categories keys baseLayer].freeze

        def self.load(path = PATH)
          table = YAML.safe_load_file(path)
          raise ConfigError.new('ファイルの先頭は Hash にしてください', path: path) unless table.is_a?(Hash)

          new(categories: table['categories'], defaults: table['defaults'], order: table['order'], contexts: table['contexts'])
        rescue Psych::Exception, Errno::ENOENT => e
          raise ConfigError.new(e.message, path: path)
        rescue ConfigError => e
          raise e if e.path

          raise ConfigError.new(e.message, path: path)
        end

        attr_reader :order

        def initialize(categories:, defaults:, order:, contexts:)
          @order = strings!(order, 'order').freeze
          @by_name = {}
          @position = {}
          hash!(categories, 'categories').each { |category, names| add_category(category, names) }
          @defaults = defaults!(defaults)
          @contexts = hash!(contexts, 'contexts').to_h { |name, value| [name, prefer!(name, value)] }.freeze
          @by_name.freeze
          @position.freeze
          freeze
        end

        # categories に書いたキーの名前（keycodes.yaml の name）すべて
        def names = @by_name.keys

        def contexts = @contexts.keys

        def category(name, section) = @by_name[name] || @defaults.fetch(section)

        def position(name) = @position[name]

        def context?(context) = @contexts.key?(context)

        def prefer?(context, category, name) = !prefer_rank(context, category, name).nil?

        # 上に出すものどうしの順（prefer.categories に書いた順、そのあとに prefer.keys のキー）。上に出さないものは nil
        def prefer_rank(context, category, name)
          prefer = fetch(context)
          rank = prefer[:categories].index(category)
          return rank if rank

          prefer[:categories].size if !name.nil? && prefer[:keys].include?(name)
        end

        def prefer_base_layer?(context) = fetch(context)[:base_layer]

        def exclude?(context, category) = fetch(context)[:exclude].include?(category)

        private

        def add_category(category, names)
          check_category!(category, 'categories')
          strings!(names, "categories.#{category}").each_with_index do |name, i|
            raise ConfigError, "キー #{name} が 2 つの分類にあります" if @by_name.key?(name)

            @by_name[name] = category
            @position[name] = i
          end
        end

        def defaults!(defaults)
          hash!(defaults, 'defaults')
          SECTIONS.to_h do |section|
            category = defaults[section.to_s] or raise ConfigError, "defaults.#{section} がありません"
            check_category!(category, "defaults.#{section}")
            [section, category]
          end.freeze
        end

        def fetch(context) = @contexts.fetch(context) { raise ArgumentError, "知らない context です: #{context.inspect}" }

        def prefer!(context, value)
          where = "contexts.#{context}"
          table = known_keys!(hash!(value, where), CONTEXT_KEYS, where)
          prefer = known_keys!(hash!(table['prefer'] || {}, "#{where}.prefer"), PREFER_KEYS, "#{where}.prefer")
          exclude = known_keys!(hash!(table['exclude'] || {}, "#{where}.exclude"), %w[categories], "#{where}.exclude")
          base_layer = prefer.fetch('baseLayer', false)
          raise ConfigError, "#{where}.prefer.baseLayer は true か false にしてください" unless [true, false].include?(base_layer)

          { categories: context_categories!(prefer, "#{where}.prefer.categories"),
            keys: strings!(prefer['keys'] || [], "#{where}.prefer.keys").freeze,
            base_layer: base_layer,
            exclude: context_categories!(exclude, "#{where}.exclude.categories") }.freeze
        end

        def context_categories!(table, where)
          categories = strings!(table['categories'] || [], where)
          categories.each { |category| check_category!(category, where) unless EXTRA_CATEGORIES.include?(category) }
          categories.freeze
        end

        def known_keys!(table, allowed, where)
          unknown = table.keys - allowed
          raise ConfigError, "#{where} に知らない項目があります: #{unknown.join(', ')}" unless unknown.empty?

          table
        end

        def check_category!(category, where)
          return if @order.include?(category)

          raise ConfigError, "#{where} の分類 #{category.inspect} が order にありません"
        end

        def hash!(value, where)
          raise ConfigError, "#{where} は Hash にしてください" unless value.is_a?(Hash)

          value
        end

        def strings!(value, where)
          raise ConfigError, "#{where} は文字列のリストにしてください" unless value.is_a?(Array) && value.all?(String)

          value
        end
      end
    end
  end
end
