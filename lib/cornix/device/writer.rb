# frozen_string_literal: true

module Cornix
  module Device
    # Plan をキーボードに書き込み、読み直して検証する（旧 Device::Keyboard#apply の書き込み部分）。
    #
    # - expected_token を渡すと plan.token と比べ、違えば何も書かずに PlanChanged（PlanError。dry run の後に差分が変わった）
    # - 書き込む前に ChangePolicy で全 Change を検査し、拒否する値があれば何も書かない
    # - 変更があるときだけ、最初の書き込みの前に backup を 1 回呼ぶ（ファイルへの保存は呼び出し側の責務。
    #   戻り値は失敗時のメッセージと結果に入る）
    # - 1 件ずつ Protocol で書き、失敗したらそこで止めて、書き込み済みの件数とバックアップを示す WriteIncomplete（DeviceError）
    # - 最後に Reader で読み直し、目標と一致しない Change を remaining に返す（読み直しに失敗したら、全件書いた WriteIncomplete）
    # - progress（省略可）は ->(phase, done, total)。書いた 1 件ごとに (:write, 件数, 全件)、読み直しは (:verify, …)（Reader の単位）
    class Writer
      def initialize(session, reader: Reader.new(session), macro_codec: Mapping::MacroCodec.new,
                     describer: ChangeDescriber.new(catalog: session.catalog),
                     policy: ChangePolicy.new(catalog: session.catalog, describer: describer))
        @session = session
        @reader = reader
        @macro_codec = macro_codec
        @describer = describer
        @policy = policy
      end

      # => ApplyResult
      def apply(plan, expected_token: nil, backup: nil, progress: nil)
        if expected_token && expected_token != plan.token
          raise PlanChanged, '差分が確認時から変わっています。もう一度 dry run で確認してください'
        end
        return ApplyResult.new if plan.empty?

        @policy.check!(plan.changes)
        backup_ref = backup&.call
        write_all(plan.changes, backup_ref, progress)
        remaining = Verification.new(verify_read(plan.changes, backup_ref, progress)).remaining(plan.changes)
        ApplyResult.new(backup: backup_ref, applied: plan.changes, remaining: remaining)
      end

      private

      attr_reader :session

      def protocol = session.protocol

      def write_all(changes, backup_ref, progress)
        changes.each_with_index do |change, i|
          begin
            write(change)
          rescue Cornix::DeviceError, ArgumentError, InvalidValue => e
            message = "#{@describer.describe(change)} の書き込みに失敗しました（#{i}/#{changes.size} 件書き込み済み）: #{e.message}"
            message += "。反映前のバックアップ: #{backup_ref}" if backup_ref
            raise WriteIncomplete.new(message, applied: i, backup: backup_ref)
          end
          progress&.call(:write, i + 1, changes.size)
        end
      end

      def verify_read(changes, backup_ref, progress)
        @reader.read(progress: progress && ->(done, total) { progress.call(:verify, done, total) })
      rescue Cornix::DeviceError => e
        message = "#{changes.size} 件を書き込みましたが、読み直しに失敗しました: #{e.message}"
        message += "。反映前のバックアップ: #{backup_ref}" if backup_ref
        raise WriteIncomplete.new(message, applied: changes.size, backup: backup_ref)
      end

      def write(change)
        case change
        when Planning::Change::SetKeycode
          protocol.set_keycode(change.layer, change.row, change.col, change.to, dims: session.dims)
        when Planning::Change::SetEncoder
          protocol.set_encoder(change.layer, change.index, change.clockwise, change.to, dims: session.dims)
        when Planning::Change::SetTapDance then write_tap_dance(change)
        when Planning::Change::SetCombo
          protocol.set_combo(change.index, change.to.keys, change.to.output, count: session.entry_counts[:combo])
        when Planning::Change::ReplaceMacros
          protocol.set_macro_buffer(@macro_codec.encode_all(change.to), size: session.macro_buffer_size)
        when Planning::Change::SetSetting then protocol.set_setting(change.qsid, change.to)
        else raise ArgumentError, "書き込み方を知らない Change です: #{change.inspect}"
        end
      end

      def write_tap_dance(change)
        td = change.to
        keys = [td.on_tap, td.on_hold, td.on_double_tap, td.on_tap_hold]
        protocol.set_tap_dance(change.index, keys, td.tapping_term, count: session.entry_counts[:tap_dance])
      end
    end
  end
end
