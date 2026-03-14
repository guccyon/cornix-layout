# frozen_string_literal: true

module Cornix
  module Models
    module Concerns
      # Validatableモジュール
      # 全モデルで共有する検証インターフェースとバリデーターを提供
      #
      # 2段階検証アプローチ:
      # - Phase 1: 構造検証（structural validation）- 依存関係不要、高速
      # - Phase 2: 意味検証（semantic validation）- 依存関係必要、Validator経由
      module Validatable
        def self.included(base)
          base.extend(ClassMethods)
        end

        # === インスタンスメソッド ===

        # 構造検証（依存なし）
        def structurally_valid?
          structural_errors.empty?
        end

        # 構造検証エラーを返す
        # サブクラスでオーバーライドして実装
        def structural_errors
          errors = []

          # クラスで定義された structural_validations を実行
          self.class.structural_validations.each do |validation|
            field = validation[:field]
            validator_type = validation[:type]
            options = validation[:options]

            # :self の場合はオブジェクト全体を、それ以外はフィールドの値を取得
            value = if field == :self
              self
            else
              instance_variable_get("@#{field}")
            end

            # :if 条件がある場合、それを評価してスキップするか判定
            if options[:if]
              condition = options[:if]
              next unless condition.call(self)
            end

            # バリデーター実行
            result = Validators.run(validator_type, value, options)
            unless result[:valid]
              message = options[:message] || result[:error]
              errors << format_error(field, message, options)
            end
          end

          errors
        end

        # セマンティック検証（依存あり）
        def semantically_valid?(context = {})
          semantic_errors(context).empty?
        end

        # セマンティック検証エラーを返す
        # サブクラスでオーバーライドして実装
        def semantic_errors(context = {})
          errors = []

          # クラスで定義された semantic_validations を実行
          self.class.semantic_validations.each do |validation|
            field = validation[:field]
            validator_type = validation[:type]
            options = validation[:options].dup

            # :self の場合はオブジェクト全体を、それ以外はフィールドの値を取得
            value = if field == :self
              self
            else
              instance_variable_get("@#{field}")
            end

            # :if 条件がある場合、それを評価してスキップするか判定
            if options[:if]
              condition = options[:if]
              next unless condition.call(self)
            end

            # コンテキストを options にマージ
            options.merge!(context)

            # バリデーター実行
            result = Validators.run(validator_type, value, options)
            unless result[:valid]
              message = options[:message] || result[:error]
              errors << format_error(field, message, options)
            end
          end

          errors
        end

        # 完全検証（構造 + 意味）
        def valid?(context = {})
          structurally_valid? && semantically_valid?(context)
        end

        # 全エラーを返す
        def all_errors(context = {})
          structural_errors + semantic_errors(context)
        end

        # 例外を投げる検証（モード制御追加）
        # @param context [Hash] 検証コンテキスト（converters, position_map等）
        # @param mode [Symbol] :strict (fail-fast) または :collect (全エラー蓄積)
        # @return [Boolean|Array] strict時はtrue、collect時はエラー配列
        def validate!(context = {}, mode: :strict)
          errors = all_errors(context)

          case mode
          when :strict
            # Fail-fast: 最初のエラーで即座に例外
            @metadata ||= {} # 未初期化の場合に備えて
            raise ValidationError.new(errors, metadata: @metadata) unless errors.empty?
            true
          when :collect
            # Collect: エラーを返すのみ（例外なし）
            errors
          else
            raise ArgumentError, "Invalid mode: #{mode} (must be :strict or :collect)"
          end
        end

        private

        def format_error(field, message, options)
          if options[:field_name]
            "#{options[:field_name]}: #{message}"
          else
            "#{field}: #{message}"
          end
        end

        # === クラスメソッド ===

        module ClassMethods
          def structural_validations
            @structural_validations ||= []
          end

          def semantic_validations
            @semantic_validations ||= []
          end

          # DSL: validates フィールド, バリデータ種別, オプション
          def validates(field, validator_type, options = {})
            phase = options.delete(:phase) || :structural

            validation = {
              field: field,
              type: validator_type,
              options: options
            }

            if phase == :structural
              structural_validations << validation
            elsif phase == :semantic
              semantic_validations << validation
            else
              raise ArgumentError, "Invalid phase: #{phase} (must be :structural or :semantic)"
            end
          end
        end
      end

      # === バリデーター実装 ===

      module Validators
        # バリデーター実行
        def self.run(type, value, options)
          case type
          when :presence
            presence(value, options)
          when :type
            type_check(value, options)
          when :format
            format_check(value, options)
          when :range
            range_check(value, options)
          when :inclusion
            inclusion_check(value, options)
          when :length
            length_check(value, options)
          when :custom
            custom_check(value, options)
          else
            { valid: false, error: "Unknown validator: #{type}" }
          end
        end

        # Presence validator
        def self.presence(value, options)
          return { valid: true } if options[:allow_nil] && value.nil?

          if value.nil? || (value.respond_to?(:empty?) && value.empty?)
            { valid: false, error: "cannot be blank" }
          else
            { valid: true }
          end
        end

        # Type validator
        def self.type_check(value, options)
          expected_type = options[:is]
          return { valid: true } if options[:allow_nil] && value.nil?

          if value.is_a?(expected_type)
            { valid: true }
          else
            { valid: false, error: "must be a #{expected_type}" }
          end
        end

        # Format validator
        def self.format_check(value, options)
          pattern = options[:with]
          return { valid: true } if options[:allow_nil] && value.nil?
          return { valid: true } if value.nil?

          if value.to_s.match?(pattern)
            { valid: true }
          else
            { valid: false, error: "format invalid" }
          end
        end

        # Range validator
        def self.range_check(value, options)
          return { valid: true } if options[:allow_nil] && value.nil?
          return { valid: false, error: "cannot be nil" } if value.nil?

          # 型チェック（数値でない場合はエラー）
          unless value.is_a?(Numeric)
            return { valid: false, error: "must be a number" }
          end

          min = options[:min]
          max = options[:max]

          errors = []
          errors << "must be >= #{min}" if min && value < min
          errors << "must be <= #{max}" if max && value > max

          if errors.empty?
            { valid: true }
          else
            { valid: false, error: errors.join(", ") }
          end
        end

        # Inclusion validator
        def self.inclusion_check(value, options)
          allowed = options[:in]
          return { valid: true } if options[:allow_nil] && value.nil?

          if allowed.include?(value)
            { valid: true }
          else
            { valid: false, error: "must be one of: #{allowed.join(', ')}" }
          end
        end

        # Length validator
        def self.length_check(value, options)
          return { valid: true } if options[:allow_nil] && value.nil?
          return { valid: false, error: "cannot be nil" } if value.nil?

          length = value.respond_to?(:size) ? value.size : value.to_s.length
          min = options[:min]
          max = options[:max]

          errors = []
          errors << "length must be >= #{min}" if min && length < min
          errors << "length must be <= #{max}" if max && length > max

          if errors.empty?
            { valid: true }
          else
            { valid: false, error: errors.join(", ") }
          end
        end

        # Custom validator
        def self.custom_check(value, options)
          validator_proc = options[:with]
          raise ArgumentError, "Custom validator requires :with proc" unless validator_proc

          # procの引数の数に応じて呼び出し方を変える
          if validator_proc.arity == 1
            validator_proc.call(value)
          elsif validator_proc.arity == 2
            validator_proc.call(value, options)
          else
            validator_proc.call(value)
          end
        end
      end

      # カスタム例外クラス
      class ValidationError < StandardError
        attr_reader :errors, :metadata

        def initialize(errors, metadata: {})
          @errors = errors.is_a?(Array) ? errors : [errors]
          @metadata = metadata # { file_path:, model_type: (optional) }
          super(format_message)
        end

        private

        def format_message
          # メタデータからファイルパスを抽出
          file_path = extract_file_path

          if file_path
            lines = ["Error in #{file_path}:"]
            @errors.each do |error|
              lines << "  - #{error}"
            end
            lines.join("\n")
          else
            "Validation Error:\n" + @errors.map { |e| "  - #{e}" }.join("\n")
          end
        end

        def extract_file_path
          return nil unless @metadata

          if @metadata.is_a?(Hash)
            @metadata[:file_path] || @metadata['file_path']
          elsif @metadata.respond_to?(:__metadata)
            meta_hash = @metadata.__metadata rescue nil
            meta_hash[:file_path] || meta_hash['file_path'] if meta_hash
          end
        end
      end
    end
  end
end
