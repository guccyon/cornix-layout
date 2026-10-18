# frozen_string_literal: true

require 'fileutils'
require 'json'

module Cornix
  module Storage
    # layout.vil（Vial の JSON）⇄ Image::DeviceImage。
    #
    # - キーコードの文字列は Mapping::VialNotation で 16bit 値にする（layout の -1 は nil）
    # - settings / layout / encoder_layout / macro / tap_dance / combo 以外のトップレベル項目は
    #   DeviceImage#meta に元の順で入れ、dump でそのまま書き戻す
    # - dump は旧 Writers::VialWriter と同じ JSON（キーの順、JSON.pretty_generate、末尾改行なし）
    #
    # 読み込みの問題（JSON の構文、形の違い、不明なキーコード）は場所（layout[2][3][1] など）付きで
    # すべて集め、Cornix::ConfigError で送出する。
    class VilFile
      # DeviceImage の各欄に入る .vil の項目
      SECTIONS = %w[settings layout encoder_layout macro tap_dance combo].freeze

      # 旧 Models::Metadata#to_qmk が SECTIONS より前に書く項目（この順）
      HEADER_KEYS = %w[version uid vial_protocol via_protocol vendor_product_id product_id matrix].freeze

      # layout でキーのない位置
      NO_KEY = -1

      def initialize(vial: Mapping::VialNotation.new)
        @vial = vial
      end

      attr_reader :vial

      # .vil ファイル → DeviceImage
      def read(path)
        parse(File.read(path, encoding: Encoding::UTF_8), path: path)
      rescue SystemCallError => e
        raise ConfigError.new("読み込めません（#{e.message}）", path: path.to_s)
      end

      # DeviceImage → .vil ファイル。書いたパスを返す
      def write(image, path)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, dump(image))
        path
      end

      # JSON 文字列 → DeviceImage（path はエラーメッセージに使う）
      def parse(json_string, path: nil)
        data = begin
          JSON.parse(json_string)
        rescue JSON::ParserError => e
          raise ConfigError.new("JSON として読めません: #{e.message.lines.first.to_s.strip}", path: path)
        end
        image, problems = Decoder.new(@vial).decode(data)
        raise ConfigError.new(problem_message(problems), path: path) unless problems.empty?

        image
      end

      # DeviceImage → JSON 文字列
      def dump(image)
        JSON.pretty_generate(Encoder.new(@vial).encode(image))
      end

      private

      def problem_message(problems)
        return problems.first if problems.size == 1

        ["#{problems.size} 件の問題があります", *problems.map { |p| "  #{p}" }].join("\n")
      end
    end
  end
end
