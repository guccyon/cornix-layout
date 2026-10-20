# frozen_string_literal: true

module Cornix
  module Mapping
    # Domain::Profile ⇄ Image::DeviceImage（compile / decompile の中心）。
    #
    # - to_image: 旧 compile（VialConfig#to_qmk）と同じ配置・パディングで DeviceImage を作る。
    #   キーのない位置と定義のないレイヤーは nil（.vil の -1）、position_map にある位置で割り当てのないものは KC_NO（0）、
    #   未使用のマクロは []、タップダンスは KC_NO × 4 + DEFAULT_TAPPING_TERM、コンボは 0 × (combo_keys + 1)
    # - to_profile: イメージを解釈して Profile にする。previous（設定ファイルから読んだ Profile）があれば
    #   同じ番号のレイヤー・マクロ・タップダンス・コンボの名前と説明、キーコードが変わっていない場所の注記、
    #   メタデータの keyboard と、extra のうち extra_keys 以外の項目、名前付きショートカットを引き継ぐ（Inheritance）。
    #   解釈できない 16bit 値は Keycode::Raw のまま持つ
    class ProfileMapper
      # 未使用のタップダンスの枠に書くタッピング時間（旧 TapDanceCollection#to_qmk_array の既定値）
      DEFAULT_TAPPING_TERM = 250

      # previous がないときのキーボード名（旧 Models::Metadata.from_qmk の固定値）
      DEFAULT_KEYBOARD = 'Cornix'

      # Domain::Metadata の項目と同じ名前の .vil のトップレベル項目（それ以外は metadata の extra_keys）
      META_FIELDS = %w[version uid vendor_product_id product_id matrix vial_protocol via_protocol].freeze

      def initialize(codec: KeycodeCodec.new, capabilities: Domain::Capabilities::CORNIX)
        @codec = codec
        @capabilities = capabilities
      end

      attr_reader :codec, :capabilities

      # Profile → DeviceImage。16bit 値にできないキーコードは UnknownKeycode、
      # デバイスの枠に収まらない番号やトリガーの数は InvalidValue
      def to_image(profile)
        raise InvalidValue, "profile は Profile です: #{profile.class}" unless profile.is_a?(Domain::Profile)

        ImageWriter.new(profile, codec: codec, capabilities: capabilities).call
      end

      # DeviceImage → Profile
      def to_profile(image, position_map:, previous: nil)
        raise InvalidValue, "image は DeviceImage です: #{image.class}" unless image.is_a?(Image::DeviceImage)
        raise InvalidValue, "position_map は PositionMap です: #{position_map.class}" unless position_map.is_a?(Domain::PositionMap)
        unless previous.nil? || previous.is_a?(Domain::Profile)
          raise InvalidValue, "previous は Profile です: #{previous.class}"
        end

        ImageReader.new(image, position_map: position_map, codec: codec, inheritance: Inheritance.new(previous)).call
      end
    end
  end
end
