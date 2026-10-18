# frozen_string_literal: true

module Cornix
  module Planning
    # デバイスへの変更 1 件（データのみ。コマンドへの変換と書き込みは Device::Writer の責務）。
    #
    # 値はすべてデバイス上の生の値（キーコード = 16bit 整数、レコード = Image の Record）。
    # 各クラスは場所の項目と from（現在の値）/ to（目標の値）を持つ。
    module Change
      # 各 Change クラスが include する共通の振る舞い
      module Value
        # 表示とハッシュに使う。キーは文字列、値は JSON にできるもの
        def to_h
          { 'kind' => kind.to_s }.merge(members.to_h { |m| [m.to_s, Change.plain(public_send(m))] })
        end

        # token の元になる値。書き込む内容（場所と to）だけで、from は含めない
        # （旧 Device::Keyboard と同じく、目標が同じなら現在の値が変わっても token は変わらない）
        def token_payload = to_h.except('from')

        def kind = self.class.name.split('::').last.gsub(/([a-z])([A-Z])/, '\1_\2').downcase.to_sym

        # 書き込むキーコード（16bit 値）の一覧。書き込みの可否の検査に使う
        def keycodes = []
      end

      def self.plain(value)
        case value
        when Data then value.to_h.transform_keys(&:to_s).transform_values { |v| plain(v) }
        when Array then value.map { |v| plain(v) }
        when Hash then value.to_h { |k, v| [k.to_s, plain(v)] }
        when Symbol then value.to_s
        when String then value.encoding == Encoding::BINARY ? value.unpack1('H*') : value
        else value
        end
      end
    end
  end
end
