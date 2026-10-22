# frozen_string_literal: true

module Cornix
  module Storage
    module Schema
      # マクロ・タップダンスのファイルから名前と番号だけを読む（問題は記録しない）。
      # Macro('名前') / TapDance('名前') の対応表（Mapping::References）を、各ファイルを読み終える前に作るため。
      # 名前や番号が正しくないファイルは対応表に入れない（その問題はファイルを読むときに報告される）。
      # index: のキーがないか値が空（null）のファイルは未使用（unused?。compile に含めない。issue #85）
      module Header
        module_function

        # 未使用のファイルの中身か（マッピングで、index がないか null）。マッピングでなければ偽（読むときに問題になる）
        def unused?(data) = data.is_a?(Hash) && data['index'].nil?

        # → [名前, 番号] または nil
        def call(data, preset: false)
          return nil unless data.is_a?(Hash)

          name = name_of(data, preset: preset)
          index = data['index']
          return nil unless name.is_a?(String) && !name.strip.empty? && index.is_a?(Integer)

          [name, index]
        end

        # ファイルの name。マクロ（preset: true）は name がなければ preset の名前（前後の空白を除く。MacroFile と同じ規則）。
        # 文字列とは限らない（検査は呼び出し側）
        def name_of(data, preset: false)
          return nil unless data.is_a?(Hash)
          return data['name'] if data.key?('name') || !preset

          data['preset'].is_a?(String) ? data['preset'].strip : nil
        end
      end
    end
  end
end
