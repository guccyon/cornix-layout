# frozen_string_literal: true

module Cornix
  module Application
    module Editor
      class ItemEdits
        # 名前の変更・preset の展開の前後で compile の結果（16bit 値）が変わる（protocol.md の 12.6 と 13.1。-32061 の reason "verify"）。
        # v0.5 の setIndex では、番号の参照を書き換えても指す先が変わる（15.3）
        # address は変えようとした場所（{ file:, path: }。名前の変更は名前、展開は preset: の場所）
        class Unverified < Cornix::Error
          REASON = 'verify'
          MESSAGES = {
            'expandPreset' => 'preset を手順に展開すると compile の結果（16bit 値）が変わるので、書き換えを作りませんでした。テキストで直してください',
            'setIndex' => '番号を変えると参照の指す先が変わるので（書き換えられない番号の参照があります）、変更を作りませんでした。テキストで直してください'
          }.freeze
          DEFAULT_MESSAGE = '名前を変えると compile の結果（16bit 値）が変わるので、書き換えを作りませんでした。テキストで直してください'

          attr_reader :address

          # op は操作の名前（約束の op の文字列）。文言を選ぶだけ
          def initialize(address:, op: nil)
            @address = address
            super(MESSAGES.fetch(op, DEFAULT_MESSAGE))
          end

          def reason = REASON
        end
      end
    end
  end
end
