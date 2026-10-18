# frozen_string_literal: true

require_relative 'checks'
require_relative 'keycode'
require_relative 'layer_ref'
require_relative 'key_position'
require_relative 'encoder_binding'

module Cornix
  module Domain
    # レイヤー 1 枚。keys は割り当てのある位置だけを持つ（ない位置はデバイスで -1 / 未設定）。
    # encoders は左右のエンコーダ（:left / :right の両方が必須）。
    # 番号がデバイスのレイヤー数に収まるか、重複がないかは Profile#diagnostics で検査する
    class Layer < Data.define(:index, :name, :description, :keys, :encoders)
      NAME_MAX = 50
      ENCODER_SIDES = %i[left right].freeze

      def initialize(index:, name:, keys:, encoders:, description: nil)
        super(
          index: Checks.integer!(index, LayerRef::RANGE, 'レイヤーの番号'),
          name: check_name!(name),
          description: Checks.text(description, 'レイヤーの説明'),
          keys: check_keys!(keys),
          encoders: check_encoders!(encoders)
        )
      end

      # 位置の割り当て。なければ nil
      def key(position) = keys[position]

      def encoder(side) = encoders.fetch(side)

      def to_s = "Layer(#{index}: #{name})"

      private

      def check_name!(name)
        Checks.name!(name, 'レイヤーの名前').tap do |n|
          raise InvalidValue, "レイヤーの名前は #{NAME_MAX} 文字までです: #{n.inspect}" if n.length > NAME_MAX
        end
      end

      def check_keys!(keys)
        Checks.hash!(keys, 'レイヤーのキー') do |pos, kc|
          Checks.instance!(pos, KeyPosition, 'キーの位置')
          Keycode.check!(kc, "#{pos} のキーコード")
        end
      end

      def check_encoders!(encoders)
        Checks.hash!(encoders, 'レイヤーのエンコーダ') do |side, binding|
          Checks.one_of!(side, ENCODER_SIDES, 'エンコーダの左右')
          Checks.instance!(binding, EncoderBinding, "#{side} のエンコーダ")
        end.tap do |h|
          missing = ENCODER_SIDES - h.keys
          raise InvalidValue, "エンコーダ #{missing.join(' / ')} がありません" unless missing.empty?
        end
      end
    end
  end
end
