# frozen_string_literal: true

module Cornix
  module Application
    module Editor
      class ItemEdits
        # 名前の変更の前後で compile の結果（16bit 値）が変わる（protocol.md の 12.6。-32061 の reason "verify"）。
        # address は変えようとした名前の場所（{ file:, path: }）
        class Unverified < Cornix::Error
          REASON = 'verify'

          attr_reader :address

          def initialize(address:)
            @address = address
            super('名前を変えると compile の結果（16bit 値）が変わるので、書き換えを作りませんでした。テキストで直してください')
          end

          def reason = REASON
        end
      end
    end
  end
end
