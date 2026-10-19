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
      #   categories.prefer?(context, category, name)  その場面で上に出すものか
      class Categories
        PATH = File.join(Cornix::DATA_DIR, 'keycode_categories.yaml')
        SECTIONS = %i[special basic quantum modified].freeze

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

        def prefer?(context, category, name)
          prefer = @contexts.fetch(context) { raise ArgumentError, "知らない context です: #{context.inspect}" }
          prefer[:categories].include?(category) || (!name.nil? && prefer[:keys].include?(name))
        end

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

        def prefer!(context, value)
          prefer = hash!(hash!(value, "contexts.#{context}")['prefer'] || {}, "contexts.#{context}.prefer")
          categories = strings!(prefer['categories'] || [], "contexts.#{context}.prefer.categories")
          categories.each { |category| check_category!(category, "contexts.#{context}.prefer.categories") }
          { categories: categories.freeze, keys: strings!(prefer['keys'] || [], "contexts.#{context}.prefer.keys").freeze }
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
