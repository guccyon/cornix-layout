# frozen_string_literal: true

module Cornix
  module Storage
    module Schema
      # position_map.yaml と layers/*.yaml の手（left_hand / right_hand）の下のグループのキー。
      # 正しい名前は Domain::PositionMap::GROUPS（row0〜row3, thumb）。親指は旧名の thumb_keys でも書ける（後方互換）。
      # 同じ手に thumb と thumb_keys の両方があれば構造の問題にする。
      #
      #   HandGroups.conflict?(hand_data, ctx, 'left_hand')   # 両方あれば問題を記録して true
      #   HandGroups.normalize(hand_data)                     # 旧名のキーを正しい名前にした Hash（並びはそのまま）
      #   HandGroups.written_key(hand_data, 'thumb')          # ファイルが書いているキー（'thumb_keys' か 'thumb'）
      #
      # エディタの Address（protocol.md）はファイルの中の道筋なので、旧名で書いたファイルでは thumb_keys を指す（written_key）
      module HandGroups
        GROUPS = Domain::PositionMap::GROUPS.keys.freeze
        LEGACY = { 'thumb_keys' => 'thumb' }.freeze # 旧名 => 正しい名前

        module_function

        def conflict?(hand_data, ctx, loc)
          return false unless hand_data.is_a?(Hash)

          both = LEGACY.select { |old, group| hand_data.key?(old) && hand_data.key?(group) }
          both.each { |old, group| ctx.problem(loc, "#{group} と #{old} の両方があります（#{old} は #{group} の旧名です。どちらか一方にしてください）") }
          !both.empty?
        end

        def normalize(hand_data)
          return hand_data unless hand_data.is_a?(Hash)

          hand_data.to_h { |key, value| [LEGACY.fetch(key, key), value] }
        end

        def written_key(hand_data, group)
          old = LEGACY.key(group)
          old && hand_data.is_a?(Hash) && hand_data.key?(old) && !hand_data.key?(group) ? old : group
        end

        # ファイルが書いているキーで並べたグループ（YamlDocument#insert の order 用）
        def written_keys(hand_data) = GROUPS.map { |group| written_key(hand_data, group) }
      end
    end
  end
end
