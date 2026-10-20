# frozen_string_literal: true

require_relative '../handler'

module Cornix
  module Interface
    module EditorServer
      module Handlers
        # profile/saved: 拡張が保存した。読み直して ProfileSnapshot を返す（protocol.md の 6.4）。
        # 知らされた版と読み直した版が違えば、応答の前に profile/didChange を送る
        class ProfileSaved < Handler
          rpc 'profile/saved'

          def call(params, context)
            id = param(params, 'profileId', String)
            files = param(params, 'files', Hash)
            files.each { |file, _| param(files, file, String, optional: true, field: "files.#{file}") }
            result = Application::Editor::Saved.new(context.workbench).call(id, files: files)
            context.notify('profile/didChange', result.notification) if result.changed?
            result.snapshot
          end
        end
      end
    end
  end
end
