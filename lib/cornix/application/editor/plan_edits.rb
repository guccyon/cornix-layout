# frozen_string_literal: true

require_relative 'profile_reading'
require_relative 'diagnostics'
require_relative 'plan_edits/errors'
require_relative 'plan_edits/targets'
require_relative 'plan_edits/draft'

module Cornix
  module Application
    module Editor
      # 未保存の変更を、ファイルの書き換え（範囲と文字）にする（protocol.md の 6.1 の profile/planEdits）。ファイルは書かない。
      #
      #   PlanEdits.new(workbench).call('p1', base_versions: { 'layers/0_base.yml' => 'sha256:…' },
      #                                       changes: [PlanEdits::Change.new(file:, path:, value:)])
      #   #=> { files: [{ file:, baseVersion:, create:, edits: [{ range:, newText: }] }], diagnostics: [Diagnostic] }
      #
      # 設定ディレクトリをいま読み、baseVersions と今の版を比べてから変更を当てる（Draft）。
      # files は書き換えのあるファイルだけ（変更を当てても中身が変わらないファイルは入れない）で、changes に初めて出てきた順。
      # create は settings/qmk_settings.yaml がなくて作るときだけ true。diagnostics は書き換えたあとの中身の検証の結果
      # （ValidateDraft と同じ。構造の問題があれば意味検証はしない）。
      # 失敗は PlanEdits::VersionConflict / InvalidChange / NotLocal（Interface が -32060 / -32602 / -32061 にする）
      class PlanEdits
        def initialize(workbench)
          @workbench = workbench
        end

        def call(id, base_versions:, changes:)
          env = @workbench.fetch(id).env
          draft = Draft.new(ProfileReading.read(env), env.settings_catalog).apply(base_versions, changes)
          { files: draft.files.map(&:to_h), diagnostics: Diagnostics.new(draft.reading, env.capabilities).call }
        end
      end
    end
  end
end
