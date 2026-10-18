# frozen_string_literal: true

module Cornix
  module Application
    # rename の提案を Claude に頼むプロンプト（旧 RenameCommand#build_analysis_prompt と同じ内容）
    module RenamePrompt
      HEADER = <<~PROMPT
        You are analyzing Cornix keyboard configuration files to suggest meaningful names.

        Task: Analyze the following macro, tap dance, combo, and layer files, then generate a JSON array of rename suggestions.

        Instructions:
        - Only suggest renames for files with generic names (matching "Macro N", "Tap Dance N", "Combo N", or "Layer N" patterns)
        - Deeply analyze key sequences and actions to infer the actual purpose
        - Preserve index prefixes (00_, 01_, 0_, 1_, etc.) in new filenames
        - For layers: use the 'description' field if meaningful, or infer from overrides
        - Output ONLY a JSON array, no other text

        JSON format:
        [
          {
            "old_path": "config/macros/00_macro.yml",
            "new_basename": "00_bracket_pair.yml",
            "content_updates": {
              "name": "Bracket Pair",
              "description": "Insert bracket pair [] with cursor positioning"
            },
            "reasoning": "Key sequence inserts brackets and positions cursor",
            "confidence": "high"
          }
        ]

        Files to analyze:

      PROMPT

      FOOTER = "\nNow generate the JSON array with rename suggestions. Output ONLY the JSON, wrapped in ```json``` code fence.\n"

      SECTIONS = { macros: 'MACRO FILES', tap_dances: 'TAP DANCE FILES', combos: 'COMBO FILES', layers: 'LAYER FILES' }.freeze

      module_function

      # files: { macros: [[表示するパス, 内容], ...], tap_dances: ..., combos: ..., layers: ... }
      def build(files)
        body = SECTIONS.map do |kind, title|
          list = files.fetch(kind, [])
          next '' if list.empty?

          "#{title}:\n\n" + list.map { |path, content| "File: #{path}\n```yaml\n#{content}\n```\n\n" }.join
        end
        HEADER + body.join + FOOTER
      end

      # Claude の出力から ```json [...] ``` の中身を取り出す（なければ nil）
      def extract_json(output) = output[/```json\s*(\[.*?\])\s*```/m, 1]
    end
  end
end
