# frozen_string_literal: true

module Cornix
  module Device
    # 現在（Reader で読んだ）と目標の DeviceImage から書き込みの Plan を作る（旧 Device::Keyboard#diff）。
    #
    # Planning::ImageDiff の変更と警告に、デバイスに依存する検査を足す:
    # - マクロ全体をバイト列にしてバッファに収まるか（収まらなければ PlanError）
    # - ChangePolicy（拒否するキーコードは PlanError、ファームウェア未対応の値は警告）
    class Planner
      def initialize(session, macro_codec: Mapping::MacroCodec.new, policy: ChangePolicy.new(catalog: session.catalog))
        @session = session
        @macro_codec = macro_codec
        @policy = policy
      end

      def plan(current:, target:)
        diff = Planning::ImageDiff.new(current: current, target: target)
        changes = diff.changes
        check_macro_size!(current, target)
        warnings = diff.warnings + @policy.check!(changes)
        Planning::Plan.new(changes: changes, warnings: warnings)
      end

      private

      def check_macro_size!(current, target)
        count = current.macros.size
        padded = (target.macros + ([[]] * count)).first(count)
        size = @macro_codec.encode_all(padded).bytesize
        limit = @session.macro_buffer_size
        raise PlanError, "マクロがバッファ (#{limit} バイト) に収まりません" if size > limit
      rescue InvalidValue => e
        raise PlanError, "マクロ: #{e.message}"
      end
    end
  end
end
