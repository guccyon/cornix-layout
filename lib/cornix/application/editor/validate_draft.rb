# frozen_string_literal: true

require_relative 'plan_edits'

module Cornix
  module Application
    module Editor
      # 未保存の変更を当てた状態でプロファイル全体を検証する（protocol.md の 5.6 の profile/validate）。ファイルは書かない。
      #
      #   ValidateDraft.new(workbench).call('p1', base_versions: { ... }, changes: [PlanEdits::Change])
      #   #=> { diagnostics: [Diagnostic] }
      #
      # 書き換えは profile/planEdits と同じ（PlanEdits::Draft）で、検証は当てたあとの中身を読み直して行う（Diagnostics）。
      # 構造の問題が 1 つでもあれば意味検証はせず構造の問題だけを返す。range は当てたあとの中身での位置。
      # 失敗も PlanEdits と同じ（版の食い違い・指せない Address・値の部分だけで書き換えられない変更）
      class ValidateDraft
        def initialize(workbench)
          @workbench = workbench
        end

        def call(id, base_versions:, changes:)
          env = @workbench.fetch(id).env
          draft = PlanEdits::Draft.new(ProfileReading.read(env), env.settings_catalog).apply(base_versions, changes)
          { diagnostics: Diagnostics.new(draft.reading, env.capabilities).call }
        end
      end
    end
  end
end
