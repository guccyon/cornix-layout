# frozen_string_literal: true

module Cornix
  module Storage
    # 設定ディレクトリのファイル構成とファイル名の規則。
    #
    #   metadata.yaml               キーボードの情報（必須）
    #   position_map.yaml           キーの名前と位置の対応（必須）
    #   settings/qmk_settings.yaml  QMK の設定（任意）
    #   shortcuts.yaml              名前付きショートカット（任意。利用者が作る）
    #   layers/{番号}_{名前}.yaml   レイヤー
    #   macros/{番号 2 桁}_{名前}.yaml、tap_dance/...、combos/...
    #
    # 拡張子は .yaml と .yml のどちらでも読む（同じ名前で両方あれば .yaml）。書くときは .yaml
    module ConfigFiles
      METADATA = 'metadata'
      POSITION_MAP = 'position_map'
      SETTINGS = 'settings/qmk_settings'
      SHORTCUTS = 'shortcuts'
      LAYERS = 'layers'
      MACROS = 'macros'
      TAP_DANCE = 'tap_dance'
      COMBOS = 'combos'
      EXTENSIONS = %w[.yaml .yml].freeze
      WRITE_EXTENSION = '.yaml'

      # 種類 => [ディレクトリ, 番号の桁数, 既定の名前の形, 既定の名前のときのファイル名]
      KINDS = {
        layers: [LAYERS, 1, /\ALayer \d+\z/, 'layer'],
        macros: [MACROS, 2, /\AMacro \d+\z/, 'macro'],
        tap_dances: [TAP_DANCE, 2, /\ATapDance \d+\z/, 'tap_dance'],
        combos: [COMBOS, 2, /\ACombo \d+\z/, 'combo']
      }.freeze

      module_function

      # 書くときの相対パス
      def single_path(base) = "#{base}#{WRITE_EXTENSION}"

      # 種類のディレクトリにある YAML ファイル（相対パス、名前順）
      def list(dir, kind)
        sub = KINDS.fetch(kind).first
        Dir.glob(File.join(dir, sub, '*.{yaml,yml}')).select { |p| File.file?(p) }
           .map { |p| "#{sub}/#{File.basename(p)}" }.sort
      end

      def directory(kind) = KINDS.fetch(kind).first

      # rel（設定ディレクトリからの相対パス）が種類のディレクトリの YAML ファイルか（list に並ぶものと同じ条件。
      # Dir.glob と同じく . で始まるファイルは含めない）
      def kind_file?(rel, kind)
        rel = rel.to_s
        File.dirname(rel) == directory(kind) && EXTENSIONS.include?(File.extname(rel)) &&
          !File.basename(rel).start_with?('.')
      end

      # 設定がすでにある（layers/ か macros/ に何かある）か。decompile が上書きを拒む条件（旧 check_config_lock と同じ）
      def populated?(dir)
        [LAYERS, MACROS].any? do |sub|
          path = File.join(dir, sub)
          File.directory?(path) && !Dir.empty?(path)
        end
      end

      # 1 つだけのファイル（base は METADATA など）の相対パス。.yaml と .yml の両方を探し、なければ nil
      def single_file(dir, base)
        EXTENSIONS.map { |ext| "#{base}#{ext}" }.find { |rel| File.file?(File.join(dir, rel)) }
      end

      # 旧 YamlWriter と同じファイル名（layers/0_base.yaml、macros/02_copy_selected.yaml）。
      # 既定の名前（"Layer 3" など）なら種類の名前、名前から英数字が残らなければ種類の名前
      def item_path(kind, index, name)
        sub, digits, default_name, fallback = KINDS.fetch(kind)
        suffix = name.match?(default_name) ? fallback : sanitize(name)
        suffix = fallback if suffix.empty?
        "#{sub}/#{index.to_s.rjust(digits, '0')}_#{suffix}#{WRITE_EXTENSION}"
      end

      # ファイル名の先頭の番号（"3_symbols.yaml" → 3）。なければ nil
      def leading_number(rel)
        m = /\A(\d+)_/.match(File.basename(rel))
        m && Integer(m[1], 10)
      end

      def sanitize(name)
        name.downcase.gsub(/[^a-z0-9]+/, '_').gsub(/^_+|_+$/, '').squeeze('_')
      end
    end
  end
end
