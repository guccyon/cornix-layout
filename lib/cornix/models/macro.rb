# frozen_string_literal: true

require_relative 'concerns/validatable'

module Cornix
  module Models
    # 1つのマクロを保持するモデル
    class Macro
      include Concerns::Validatable

      # MacroAction - QMK Macro アクション型のバリューオブジェクト
      class MacroAction
        VALID_ACTIONS = %w[tap down up delay beep text].freeze

        attr_reader :type

        def initialize(type)
          unless VALID_ACTIONS.include?(type)
            raise ArgumentError, "Invalid action type: #{type}. Must be one of #{VALID_ACTIONS.join(', ')}"
          end
          @type = type
        end

        def requires_keys?
          %w[tap down up].include?(@type)
        end

        def requires_duration?
          @type == 'delay'
        end

        def standalone?
          @type == 'beep'
        end

        def ==(other)
          other.is_a?(MacroAction) && @type == other.type
        end

        def to_s
          @type
        end

        def inspect
          "#<MacroAction type=#{@type}>"
        end
      end

      # MacroStep - マクロの1ステップを表現するモデル
      class MacroStep
        include Concerns::Validatable

        attr_reader :action, :keys, :duration, :content

        # Structural validations
        validates :action, :presence
        validates :action, :type, is: String
        validates :action, :inclusion, in: MacroAction::VALID_ACTIONS

        validates :keys, :type, is: Array, if: ->(step) {
          # actionが有効な値の場合のみMacroActionを初期化
          return false unless step.action.is_a?(String) && MacroAction::VALID_ACTIONS.include?(step.action)
          action_obj = MacroAction.new(step.action)
          action_obj.requires_keys?
        }

        validates :keys, :custom, with: ->(value) {
          if value.nil? || value.empty?
            { valid: false, error: "cannot be empty" }
          else
            { valid: true }
          end
        }, if: ->(step) {
          # tap/down/upの場合のみ空配列チェック
          return false unless step.action.is_a?(String) && MacroAction::VALID_ACTIONS.include?(step.action)
          action_obj = MacroAction.new(step.action)
          action_obj.requires_keys?
        }

        validates :duration, :type, is: Integer, if: ->(step) {
          # actionが有効な値の場合のみMacroActionを初期化
          return false unless step.action.is_a?(String) && MacroAction::VALID_ACTIONS.include?(step.action)
          action_obj = MacroAction.new(step.action)
          action_obj.requires_duration?
        }

        # Semantic validations
        validates :keys, :custom, phase: :semantic, with: ->(value, options) {
          return { valid: true } if value.nil? || value.empty?

          keycode_converter = options[:keycode_converter]
          unless keycode_converter
            return { valid: false, error: 'keycode_converter is required' }
          end

          errors = []
          value.each_with_index do |key, idx|
            resolved = keycode_converter.resolve(key)
            unless resolved
              errors << "keys[#{idx}]: Invalid keycode '#{key}'"
            end
          end

          if errors.empty?
            { valid: true }
          else
            { valid: false, error: errors.join('; ') }
          end
        }

        validates :duration, :custom, phase: :semantic, with: ->(value, options) {
          return { valid: true } if value.nil?

          if value < 0
            { valid: false, error: "must be non-negative (got #{value})" }
          else
            { valid: true }
          end
        }, if: ->(step) { step.action == 'delay' }

        def initialize(action:, keys: nil, duration: nil, content: nil)
          @action = action
          @keys = keys
          @duration = duration
          @content = content
        end

        def self.from_yaml_hash(hash)
          # keysがStringの場合（単一キー）は配列に変換
          keys = hash['keys']
          keys = [keys] if keys.is_a?(String)
          new(
            action: hash['action'],
            keys: keys,
            duration: hash['duration'],
            content: hash['content']
          )
        end

        def to_yaml_hash
          hash = { 'action' => @action }
          hash['keys'] = @keys if @keys
          hash['duration'] = @duration if @duration
          hash['content'] = @content if @content
          hash
        end

        def to_qmk(keycode_converter, reference_converter: nil)
          case @action
          when 'tap', 'down', 'up'
            resolved_keys = @keys.map { |key| keycode_converter.resolve(key) }
            [@action] + resolved_keys
          when 'delay'
            ['delay', @duration]
          when 'beep'
            ['beep']
          end
        end

        def self.from_qmk(qmk_array, keycode_converter, reference_converter: nil)
          action = qmk_array[0]

          case action
          when 'tap', 'down', 'up'
            keys = qmk_array[1..-1].map { |qmk_key| keycode_converter.reverse_resolve(qmk_key) }
            new(action: action, keys: keys)
          when 'delay'
            new(action: action, duration: qmk_array[1])
          when 'beep'
            new(action: action)
          else
            raise ArgumentError, "Unknown macro action: #{action}"
          end
        end

        def ==(other)
          other.is_a?(MacroStep) &&
            @action == other.action &&
            @keys == other.keys &&
            @duration == other.duration
        end

        def inspect
          parts = ["action=#{@action}"]
          parts << "keys=#{@keys.inspect}" if @keys
          parts << "duration=#{@duration}" if @duration
          "#<MacroStep #{parts.join(', ')}>"
        end
      end

      # === Macro本体 ===

      attr_reader :index, :name, :description, :sequence

      # Structural validations
      validates :index, :presence
      validates :index, :type, is: Integer
      validates :index, :custom, with: ->(value) {
        return { valid: false, error: "must be between 0 and 31" } if value.nil?

        if value >= 0 && value < 32
          { valid: true }
        else
          { valid: false, error: "must be between 0 and 31" }
        end
      }
      validates :name, :presence
      validates :name, :type, is: String
      validates :sequence, :presence
      validates :sequence, :type, is: Array
      validates :sequence, :custom, with: ->(value) {
        return { valid: true } if value.nil? || !value.is_a?(Array)

        invalid_steps = value.select { |step| !step.is_a?(MacroStep) }
        if invalid_steps.empty?
          { valid: true }
        else
          { valid: false, error: "contains non-MacroStep elements (#{invalid_steps.size} items)" }
        end
      }

      # Semantic validations
      validates :sequence, :custom, phase: :semantic, with: ->(value, options) {
        return { valid: true } if value.nil?
        return { valid: true } unless value.is_a?(Array)
        return { valid: true } if value.empty?

        # Extract only context keys (exclude validation framework keys like :with)
        context = options.slice(:keycode_converter, :reference_converter, :position_map, :config_dir)

        errors = []
        value.each_with_index do |step, idx|
          next unless step.respond_to?(:validate!)

          # 子モデルの全エラー（structural + semantic）を収集
          begin
            step_errors = step.validate!(context, mode: :collect)
            step_errors.each { |e| errors << "sequence[#{idx}]: #{e}" }
          rescue => e
            errors << "sequence[#{idx}]: validation failed: #{e.message}"
          end
        end

        if errors.empty?
          { valid: true }
        else
          { valid: false, error: errors.join('; ') }
        end
      }

      def initialize(index:, name:, description:, sequence:)
        @index = index
        @name = name
        @description = description
        @sequence = sequence
      end

      def self.from_qmk(index, qmk_array, keycode_converter:, reference_converter: nil)
        steps = qmk_array.map do |qmk_step|
          MacroStep.from_qmk(qmk_step, keycode_converter, reference_converter: reference_converter)
        end

        new(
          index: index,
          name: "Macro #{index}",
          description: '',
          sequence: steps
        )
      end

      def to_qmk(keycode_converter:, reference_converter: nil)
        @sequence.map do |step|
          step.to_qmk(keycode_converter, reference_converter: reference_converter)
        end
      end

      def self.from_yaml_hash(yaml_hash)
        metadata = yaml_hash.respond_to?(:__metadata) ? yaml_hash.__metadata : {}

        sequence_array = yaml_hash['sequence'] || []
        sequence = sequence_array.map do |step_hash|
          MacroStep.from_yaml_hash(step_hash)
        end

        instance = new(
          index: yaml_hash['index'],
          name: yaml_hash['name'],
          description: yaml_hash['description'] || '',
          sequence: sequence
        )

        instance.instance_variable_set(:@metadata, metadata)

        instance
      end

      def to_yaml_hash
        {
          'index' => @index,
          'name' => @name,
          'description' => @description,
          'sequence' => @sequence.map(&:to_yaml_hash)
        }
      end

      def empty?
        @sequence.nil? || @sequence.empty?
      end
    end
  end
end
