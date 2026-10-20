# frozen_string_literal: true

require_relative 'invalid_change'

module Cornix
  module Application
    module Editor
      class PlanEdits
        # Change を当てる直前の中身で、宛先を確かめる（並びの位置・手順の action・注記を書く割り当てがあるか）。
        # 並びの中を指す Address は、それより前の Change を当てたあとの位置で数える（protocol.md の 12.3）ので、
        # Targets（道筋の形）では決められない分をここで見る。合わなければ InvalidChange
        # （宛先は changes[i].address、挿入の位置は changes[i].index、移動は changes[i].from / changes[i].to）。
        #
        #   StateCheck.new(data).call(target, change, i)   # data は当てる直前の中身を YAML として読んだもの（読めなければ nil）
        class StateCheck
          KEY_ACTIONS = Storage::Schema::MacroFile::KEY_ACTIONS.keys.freeze

          def initialize(data)
            @data = data
          end

          def call(target, change, index)
            @change = change
            @index = index
            size = send(:"#{target.check}_size") if target.check
            check_bounds!(size) if %i[insert move].include?(change.op)
            check_assignment! if change.op == :set && change.note?
          end

          private

          def path = @change.path

          def invalid!(field, message)
            raise InvalidChange.new("changes[#{@index}].#{field}", message)
          end

          def unknown! = invalid!('address', "変更の宛先を指せません: #{path.join('.')}")

          # 並びの要素（[..., i]）。並びがあり、i がその中
          def element_size
            list = dig(path[0...-1])
            unknown! unless list.is_a?(Array) && path.last.between?(0, list.size - 1)
            nil
          end

          # 並び（["sequence"]、["trigger_keys"]）の長さ。値なしで書いてあれば 0（挿入だけできる）
          def list_size
            list = dig(path)
            return list.size if list.is_a?(Array)
            return 0 if list.nil? && @change.op == :insert && written?(path)

            unknown!
          end

          # 手順のキー（["sequence", i, "keys"]）: tap / down / up の手順。set と remove は 1 つの値で書いたときだけ
          # （並びで書いていれば要素を ["sequence", i, "keys", j] で指す）。並びとしての長さは 1 つの値なら 1
          def step_keys_size
            step = step_with(KEY_ACTIONS)
            keys = step['keys']
            single = keys.is_a?(String) || keys.is_a?(Integer)
            unknown! if %i[set remove].include?(@change.op) && !single
            return keys.size if keys.is_a?(Array)
            return 1 if single
            return 0 if keys.nil? && @change.op == :insert && step.key?('keys')

            unknown!
          end

          def step_delay_size = step_with(['delay']) && nil

          def step_text_size = step_with(['text']) && nil

          def step_with(actions)
            step = dig(path[0, 2])
            unknown! unless step.is_a?(Hash) && actions.include?(step['action'])
            step
          end

          def check_bounds!(size)
            if @change.op == :insert
              return if @change.index.between?(0, size)

              invalid!('index', "挿入の位置が並びの外です: #{@change.index}（0 から #{size}）")
            end
            %i[from to].each do |name|
              value = @change.public_send(name)
              invalid!(name.to_s, "移動の位置が並びの外です: #{value}（0 から #{size - 1}）") unless value.between?(0, size - 1)
            end
          end

          # 注記を書くには割り当てが要る（割り当てのない場所に注記だけは書かない）
          def check_assignment!
            return unless dig(path).nil?

            invalid!('address', "割り当てのない場所には注記を書けません（先にキーを割り当ててください）: #{path.join('.')}")
          end

          # path の最後のキーが（値なしでも）書いてあるか
          def written?(keys)
            parent = dig(keys[0...-1])
            parent.is_a?(Hash) && parent.any? { |k, _| k.to_s == keys.last.to_s }
          end

          # 中身を path で辿った値（なければ nil）。マッピングのキーは文字列として比べる（数字だけの名前も）
          def dig(keys)
            keys.reduce(@data) do |node, key|
              case node
              when Hash then node.fetch(key) { node.find { |k, _| k.to_s == key.to_s }&.last }
              when Array then key.is_a?(Integer) && key >= 0 ? node[key] : nil
              end
            end
          end
        end
      end
    end
  end
end
