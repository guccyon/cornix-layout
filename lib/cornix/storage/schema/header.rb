# frozen_string_literal: true

module Cornix
  module Storage
    module Schema
      # マクロ・タップダンスのファイルから名前と番号だけを読む（問題は記録しない）。
      # Macro('名前') / TapDance('名前') の対応表（Mapping::References）を、各ファイルを読み終える前に作るため。
      # 名前や番号が正しくないファイルは対応表に入れない（その問題はファイルを読むときに報告される）
      module Header
        module_function

        # → [名前, 番号] または nil
        def call(data)
          return nil unless data.is_a?(Hash)

          name = data['name']
          index = data['index']
          return nil unless name.is_a?(String) && !name.strip.empty? && index.is_a?(Integer)

          [name, index]
        end
      end
    end
  end
end
