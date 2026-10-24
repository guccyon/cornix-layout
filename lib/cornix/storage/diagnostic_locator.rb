# frozen_string_literal: true

require_relative 'yaml_file'
require_relative 'config_files'
require_relative 'file_source'
require_relative 'problem'
require_relative 'schema/header'
require_relative 'schema/hand_groups'
require_relative 'schema/layer_file'

module Cornix
  module Storage
    # Profile#diagnostics のモデル内パスを設定ファイル上の位置にする（validate の表示用）。
    #
    #   layers[0].left_hand.row0.tab          → layers/0_base.yml: mapping.left_hand.row0.tab
    #   layers[0].encoders.right.push         → layers/0_base.yml: mapping.encoders.right.push
    #   macros[2].steps[1].keys[0]            → macros/02_copy.yml: sequence[1].keys[0]
    #   tap_dances[1].on_hold                 → tap_dance/01_x.yml: actions.on_hold
    #   combos[0].trigger_keys[1]             → combos/00_x.yml: trigger_keys[1]
    #   combos[0].output_key                  → combos/00_x.yml: output_key.key（注記付きの形 { key:, note: } のとき）
    #   macros                                → macros/
    #
    # layers[i] などの i は Profile の配列の位置で、ConfigLoader は各ディレクトリのファイルを名前順に読み、
    # 未使用のファイル（index のないもの。Schema::Header.unused?）は Profile に入れないので、
    # 未使用のファイルを除いて名前順に並べた i 番目のファイルに対応する（issue #85。除かないと後ろの項目が別のファイルを指す）。
    # ファイルの中身（actions: の有無、keys が 1 つだけの文字列か）も見て位置を決める。
    # ファイルは source（FileSource。既定はディスクの dir）から読むので、保存前の中身でも位置を決められる。
    #
    #   locator.address('layers[0].left_hand.row0.tab')   # => ["layers/0_base.yml", ["mapping", "left_hand", "row0", "tab"]]
    #   locator.address('combos[0].output_key')            # => ["combos/00_x.yml", ["output_key"]]（注記付きでも .key を付けない）
    class DiagnosticLocator
      KINDS = { 'layers' => :layers, 'macros' => :macros, 'tap_dances' => :tap_dances, 'combos' => :combos }.freeze
      ITEM = /\A(#{KINDS.keys.join('|')})\[(\d+)\](?:\.(.+))?\z/
      COLLECTION = /\A(#{KINDS.keys.join('|')})\z/
      LAYER_MAPPING = /\A(?:left_hand|right_hand|encoders)(?:\.|\z)/
      MACRO_STEP = /\Asteps\[(\d+)\](.*)\z/
      MACRO_KEY = /\A\.keys\[\d+\]\z/

      # dir は既定の source（ディスク）を作るためだけに使う。ファイルはすべて source から読む
      def initialize(dir, source: FileSource::Disk.new(dir))
        @source = source
        @files = {}
        @contents = {}
      end

      # Domain::Diagnostic → path を「ファイル: キーの位置」にした Domain::Diagnostic
      def locate(diagnostic)
        Domain::Diagnostic.new(severity: diagnostic.severity, path: locate_path(diagnostic.path),
                               message: diagnostic.message)
      end

      # モデル内のパス → 「ファイル: キーの位置」。変換できないパスはそのまま
      def locate_path(model_path)
        path = model_path.to_s
        if (m = ITEM.match(path))
          item(KINDS.fetch(m[1]), Integer(m[2], 10), m[3])
        elsif (m = COLLECTION.match(path))
          "#{ConfigFiles.directory(KINDS.fetch(m[1]))}/"
        else
          path
        end
      end

      # モデル内のパス → [ファイル, キーの道筋]（protocol.md の Address の形）。注記付きの形でも .key を付けない。
      # ファイル全体のパス（layers[0]）は道筋が []。一覧全体・ファイルがない番号・知らないパスは nil
      def address(model_path)
        m = ITEM.match(model_path.to_s) or return nil
        kind = KINDS.fetch(m[1])
        rel = files(kind)[Integer(m[2], 10)] or return nil
        rest = m[3]
        return [rel, []] if rest.nil? || rest.empty?

        [rel, Problem.path_of(location(kind, rel, rest))]
      end

      private

      def item(kind, position, rest)
        rel = files(kind)[position]
        return "#{ConfigFiles.directory(kind)}/（#{position + 1} 番目のファイル）#{rest && ": #{rest}"}" unless rel
        return rel if rest.nil? || rest.empty?

        "#{rel}: #{assignment_key(rel, location(kind, rel, rest))}"
      end

      def location(kind, rel, rest) = send(:"#{kind}_location", rel, rest)

      # グループはファイルが書いているキーにする（旧名の thumb_keys で書いていれば layers[0].left_hand.thumb.x → mapping.left_hand.thumb_keys.x）
      def layers_location(rel, rest)
        return rest unless rest.match?(LAYER_MAPPING)

        hand, group, tail = rest.split('.', 3)
        return "mapping.#{rest}" unless group && Schema::HandGroups::GROUPS.include?(group)

        key = Schema::HandGroups.written_key(Schema::LayerFile.hands(content(rel))[hand], group)
        ['mapping', hand, key, tail].compact.join('.')
      end

      # preset: のマクロ（sequence がない）は手順の場所を preset にする
      def macros_location(rel, rest)
        m = MACRO_STEP.match(rest) or return rest
        data = content(rel)
        return 'preset' if data.is_a?(Hash) && data.key?('preset') && !data.key?('sequence')

        tail = m[2]
        step = data.then { |d| d.is_a?(Hash) && d['sequence'].is_a?(Array) ? d['sequence'][Integer(m[1], 10)] : nil }
        tail = '.keys' if tail.match?(MACRO_KEY) && step.is_a?(Hash) && step['keys'].is_a?(String)
        "sequence[#{m[1]}]#{tail}"
      end

      def tap_dances_location(rel, rest)
        action = Domain::TapDance::ACTIONS.map(&:to_s).include?(rest)
        data = content(rel)
        action && data.is_a?(Hash) && data.key?('actions') ? "actions.#{rest}" : rest
      end

      def combos_location(_rel, rest) = rest

      # 位置の値が注記付きの形（{ key:, note: }）ならキーコードの位置（.key）にする
      def assignment_key(rel, location)
        value = location.split('.').reduce(content(rel)) do |node, key|
          node.is_a?(Hash) ? node.fetch(key) { node[Integer(key, 10, exception: false)] } : nil
        end
        value.is_a?(Hash) && value.key?('key') ? "#{location}.key" : location
      end

      # 使っているファイル（Profile の並びと同じ）。YAML として読めないファイルは使っているほうに数える（ConfigLoader と同じ）
      def files(kind) = @files[kind] ||= @source.list(kind).reject { |rel| Schema::Header.unused?(content(rel)) }

      def content(rel)
        return @contents[rel] if @contents.key?(rel)

        @contents[rel] = begin
          YamlFile.parse(@source.read(rel))
        rescue YamlFile::Unreadable, SystemCallError
          nil
        end
      end
    end
  end
end
