# frozen_string_literal: true

module Cornix
  module Application
    module Editor
      # 知らない context（data/keycode_categories.yaml の contexts にない）。Interface が -32602（data: { field: "context" }）にする。
      #
      #   UnknownContext.check!('layerKey')   # 知っていれば context を返す。知らなければ送出する
      class UnknownContext < Cornix::Error
        attr_reader :context

        def self.check!(context, categories: Mapping::CandidateCatalog.default_categories)
          raise new(context) unless categories.context?(context)

          context
        end

        def initialize(context)
          @context = context
          super("知らない context です: #{context.inspect}")
        end
      end
    end
  end
end
