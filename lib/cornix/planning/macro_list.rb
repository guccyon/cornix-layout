# frozen_string_literal: true

module Cornix
  module Planning
    # マクロの動作列をバイト列にしたときに同じになるものどうしで比べるための正規化。
    #
    # Vial のバイト列では [tap A][tap B] と [tap A, B]、続けて書いた text どうしは区別できず、
    # 空の tap や空の text は消える。デバイスから読んだマクロ（MacroCodec#decode の結果）はこの正規形になっている。
    module MacroList
      KEY_KINDS = %i[tap down up].freeze

      module_function

      # [Image::MacroAction] → 正規形の [Image::MacroAction]
      def normalize(actions)
        actions.each_with_object([]) do |action, out|
          next if empty_action?(action)

          action = action.with(value: text_value(action.value)) if action.kind == :text

          last = out.last
          if last && mergeable?(last, action)
            out[-1] = merge(last, action)
          else
            out << action
          end
        end
      end

      def same?(a, b) = normalize(a) == normalize(b)

      def empty_action?(action)
        return action.keys.empty? if KEY_KINDS.include?(action.kind)

        action.kind == :text && action.value.to_s.empty?
      end

      # バイト列が同じ text が同じ値になるよう、UTF-8 として正しければ UTF-8、そうでなければバイト列にする
      def text_value(value)
        text = value.to_s.b.force_encoding(Encoding::UTF_8)
        text.valid_encoding? ? text : text.b
      end

      def mergeable?(last, action)
        last.kind == action.kind && (KEY_KINDS.include?(action.kind) || action.kind == :text)
      end

      def merge(last, action)
        if action.kind == :text
          last.with(value: text_value(last.value.to_s.b + action.value.to_s.b))
        else
          last.with(keys: last.keys + action.keys)
        end
      end
    end
  end
end
