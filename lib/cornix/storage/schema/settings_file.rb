# frozen_string_literal: true

module Cornix
  module Storage
    module Schema
      # settings/qmk_settings.yaml（Vial の QMK Settings。名前は Mapping::QmkSettingCatalog）
      #
      #   keyboard:
      #     tapping_term: 180
      #     permissive_hold: false       # 真偽値の設定は true / false（0 / 1 も可）
      #   vial:
      #     combo_timing_window: 50
      #
      # 旧 decompile が書いた QSID の番号の形（'7': 180）も読む。書くときは名前の形にする
      # （カタログにない QSID だけは番号の形で残す）
      module SettingsFile
        GROUP_ORDER = %w[keyboard vial].freeze
        QSID_KEY = /\A\d+\z/

        module_function

        def read(data, ctx, catalog)
          return Domain::QmkSettings::EMPTY if data.nil?

          # QSID の番号は引用符なし（整数のキー）でもよいので、キーの型はここで調べる
          return ctx.type_error(data, '', 'マッピング（キー: 値）') unless data.is_a?(Hash)

          hash = data
          values = {}
          ok = true
          hash.each do |key, raw|
            ok = false unless read_entry(key, raw, ctx, catalog, values)
          end
          return nil unless ok

          ctx.build('') { Domain::QmkSettings.new(values: values) }
        end

        def read_entry(key, raw, ctx, catalog, values)
          return ctx.problem('', Pitfalls.key_message(key, '設定のグループ')) unless key.is_a?(String) || key.is_a?(Integer)

          if key.is_a?(Integer) || key.match?(QSID_KEY)
            qsid = Integer(key.to_s, 10)
            return store(qsid, read_value(catalog.fetch(qsid), raw, ctx, key.to_s), ctx, key.to_s, values)
          end
          return read_group(key, raw, ctx, catalog, values) if groups(catalog).include?(key)

          ctx.problem(key, "未知のキーです（使えるキー: #{groups(catalog).join(', ')}、または QSID の番号）")
        end

        def read_group(group, raw, ctx, catalog, values)
          return true if raw.nil?

          hash = ctx.mapping(raw, group, key_label: '設定の名前') or return false
          hash.select { |name, _| name.is_a?(String) }.map do |name, value|
            loc = "#{group}.#{name}"
            definition = catalog.find(group, name)
            next unknown_setting(ctx, catalog, group, loc) unless definition

            store(definition.qsid, read_value(definition, value, ctx, loc), ctx, loc, values)
          end.all?
        end

        def unknown_setting(ctx, catalog, group, loc)
          names = catalog.all.select { |d| d.group == group }.map(&:name)
          ctx.problem(loc, "未知の設定です（使える設定: #{names.join(', ')}）")
          false
        end

        def store(qsid, value, ctx, loc, values)
          return false if value.nil?
          if values.key?(qsid)
            ctx.problem(loc, "QSID #{qsid} の設定が 2 回書かれています")
            return false
          end

          values[qsid] = value
          true
        end

        # 真偽値は 0 / 1。整数は設定の幅に収まること
        def read_value(definition, raw, ctx, loc)
          return raw ? 1 : 0 if [true, false].include?(raw)

          expected = definition&.boolean? ? 'true / false' : '0 以上の整数'
          value = ctx.integer(raw, loc, expected) or return nil
          max = definition ? definition.max : Domain::QmkSettings::VALUE_RANGE.end
          return value if value.between?(0, max)

          ctx.problem(loc, "値は 0〜#{max} です: #{value}")
        end

        def groups(catalog)
          (GROUP_ORDER + catalog.all.map(&:group)).uniq
        end

        # 名前の形（グループ → 名前、QSID の順）。真偽値の設定で 0 / 1 なら true / false
        def write(settings, catalog)
          out = {}
          unknown = {}
          settings.values.each do |qsid, value|
            definition = catalog.fetch(qsid)
            next unknown[qsid.to_s] = value unless definition

            (out[definition.group] ||= {})[definition.name] = write_value(definition, value)
          end
          ordered = groups(catalog).filter_map { |g| [g, out[g]] if out.key?(g) }.to_h
          ordered.merge(unknown)
        end

        def write_value(definition, value)
          definition.boolean? && [0, 1].include?(value) ? value == 1 : value
        end
      end
    end
  end
end
