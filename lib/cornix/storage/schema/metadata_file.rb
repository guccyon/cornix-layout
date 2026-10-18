# frozen_string_literal: true

module Cornix
  module Storage
    module Schema
      # metadata.yaml
      #
      #   keyboard: cornix                  # 必須
      #   version: 1                        # 必須（layout.vil の version）
      #   uid: 16882930253541522617
      #   vial_protocol: 6
      #   via_protocol: 9
      #   extra_keys: { layout_options: 0, alt_repeat_key: [], key_override: [] }
      #   file_naming: ...                  # ほかの項目はそのまま保持する（Domain::Metadata#extra）
      module MetadataFile
        INTEGERS = %w[version uid vial_protocol via_protocol].freeze

        module_function

        def read(data, ctx)
          hash = ctx.mapping(data, '', required: %w[keyboard version]) or return nil
          ok = !ctx.name(hash['keyboard'], 'keyboard', 'キーボードの名前（文字列）').nil?
          INTEGERS.each do |key|
            next if hash[key].nil? && key != 'version'

            ok = false unless ctx.integer(hash[key], key, '0 以上の整数')
          end
          ok = false unless check_optional(hash, ctx)
          return nil unless ok && hash.keys.all?(String)

          ctx.build('') { Domain::Metadata.from_h(hash) }
        end

        def check_optional(hash, ctx)
          ok = true
          unless hash['vendor_product_id'].nil?
            ok = false unless ctx.string(hash['vendor_product_id'], 'vendor_product_id', '"0xXXXX" の形の文字列')
          end
          unless hash['matrix'].nil?
            ok = false unless ctx.mapping(hash['matrix'], 'matrix', required: %w[rows cols])
          end
          ok
        end

        # 旧 YamlWriter と同じ順（keyboard, version, uid, ...）。値のない項目は書かない
        def write(metadata) = metadata.to_h
      end
    end
  end
end
