# frozen_string_literal: true

module Cornix
  module Planning
    # 現在（デバイスから読んだ）と目標（layout.vil など）の DeviceImage を比べ、書き込む Change と警告を列挙する。
    #
    # current がデバイスの形（レイヤー数、キーのある位置、エンコーダ数、TD / コンボ / マクロの枠数、扱える設定）を決める。
    # 旧 Device::Keyboard#diff と同じく、次の順に比べる: キー → エンコーダ → タップダンス → コンボ → マクロ → 設定。
    # - 目標のレイヤー数がデバイスより多い、デバイスの枠を超えるマクロに中身がある → PlanError
    # - デバイスにキーがない位置（current が nil）の値、目標で nil（.vil の -1）の位置、枠を超える TD / コンボ、
    #   デバイスが扱わない設定 → 警告して無視
    # キーコードの書き込み可否（boot 系など）とマクロのバイト数は Device 側で検査する。
    class ImageDiff
      attr_reader :current, :target

      def initialize(current:, target:)
        @current = current
        @target = target
      end

      # => [Change]（旧 Device::Keyboard と同じ順）
      def changes
        compute
        @changes
      end

      # => [String]
      def warnings
        compute
        @warnings
      end

      private

      def compute
        return if @changes

        changes = []
        warnings = []
        diff_layers(changes, warnings)
        diff_encoders(changes, warnings)
        diff_tap_dances(changes, warnings)
        diff_combos(changes, warnings)
        diff_macros(changes)
        diff_settings(changes, warnings)
        warnings.concat(meta_warnings)
        @warnings = warnings.freeze
        @changes = changes.freeze
      end

      def diff_layers(changes, warnings)
        count = current.layers.size
        layers = target.layers
        raise PlanError, "レイヤー数がキーボード (#{count}) より多い: #{layers.size}" if layers.size > count

        warnings << "layout.vil のレイヤー数 (#{layers.size}) がキーボード (#{count}) より少ない" if layers.size < count
        layers.each_with_index do |rows, l|
          rows.each_with_index do |cols, r|
            cols.each_with_index do |to, c|
              change = key_change(l, r, c, to, warnings)
              changes << change if change
            end
          end
        end
      end

      def key_change(layer, row, col, to, warnings)
        where = "レイヤー#{layer} (#{row},#{col})"
        from = current.layers.dig(layer, row, col)
        if from.nil?
          warnings << "#{where} はキーボード上に存在しない位置のため無視します" unless to.nil?
          return nil
        end
        if to.nil?
          warnings << "#{where} が layout.vil で -1 のため無視します"
          return nil
        end
        Change::SetKeycode.new(layer: layer, row: row, col: col, from: from, to: to) unless from == to
      end

      def diff_encoders(changes, warnings)
        target.encoders.each_with_index do |records, l|
          next if l >= current.encoders.size

          records.each_with_index do |to, e|
            from = current.encoders[l][e]
            if from.nil?
              warnings << "レイヤー#{l} エンコーダ#{e} はキーボードに存在しないため無視します"
              next
            end
            [[false, :ccw], [true, :cw]].each do |clockwise, dir|
              a = from.public_send(dir)
              b = to.public_send(dir)
              changes << Change::SetEncoder.new(layer: l, index: e, clockwise: clockwise, from: a, to: b) unless a == b
            end
          end
        end
      end

      def diff_tap_dances(changes, warnings)
        target.tap_dances.each_with_index do |to, i|
          from = current.tap_dances[i]
          if from.nil?
            keys = [to.on_tap, to.on_hold, to.on_double_tap, to.on_tap_hold]
            warnings << "タップダンス#{i} はキーボードの上限を超えるため無視します" unless keys.all?(&:zero?)
            next
          end
          changes << Change::SetTapDance.new(index: i, from: from, to: to) unless from == to
        end
      end

      def diff_combos(changes, warnings)
        target.combos.each_with_index do |to, i|
          from = current.combos[i]
          if from.nil?
            warnings << "コンボ#{i} はキーボードの上限を超えるため無視します" unless [*to.keys, to.output].all?(&:zero?)
            next
          end
          changes << Change::SetCombo.new(index: i, from: from, to: to) unless from == to
        end
      end

      def diff_macros(changes)
        count = current.macros.size
        macros = target.macros
        if macros.size > count && macros[count..].any? { |m| !MacroList.normalize(m).empty? }
          raise PlanError, "マクロ数がキーボードの上限 (#{count}) を超えています"
        end

        padded = (macros + ([[]] * count)).first(count)
        indexes = (0...count).reject { |i| MacroList.same?(current.macros[i], padded[i]) }
        changes << Change::ReplaceMacros.new(indexes: indexes, from: current.macros, to: padded) unless indexes.empty?
      end

      def diff_settings(changes, warnings)
        target.settings.each do |qsid, to|
          unless current.settings.key?(qsid)
            warnings << "設定 #{qsid} はこのキーボードでは扱えないため無視します"
            next
          end
          from = current.settings[qsid]
          changes << Change::SetSetting.new(qsid: qsid, from: from, to: to) unless from == to
        end
      end

      def meta_warnings
        meta = target.meta
        warnings = []
        warnings << 'layout_options はキーボードへ反映しません' if meta.fetch('layout_options', 0).to_i != 0
        %w[key_override alt_repeat_key].each do |key|
          warnings << "#{key} はこのキーボードが対応していないため反映しません" if Array(meta[key]).any?
        end
        warnings
      end
    end
  end
end
