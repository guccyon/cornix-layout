# frozen_string_literal: true

require 'spec_helper'

# 依存の向き（docs/architecture.md）をソースの参照で検査する。
# 各レイヤーのファイルが、許されていないレイヤーの名前空間を参照していないこと。
RSpec.describe 'レイヤーの依存の向き' do
  allowed = {
    'domain' => %w[Domain],
    'image' => %w[Image],
    'mapping' => %w[Mapping Domain Image],
    'planning' => %w[Planning Image],
    'storage' => %w[Storage Domain Image Mapping],
    'device' => %w[Device Image Planning Mapping],
    'application' => %w[Application Domain Image Mapping Planning Storage Device],
    'interface' => %w[Interface Application]
  }
  layers = %w[Domain Image Mapping Planning Storage Device Application Interface]
  root = File.expand_path('../lib/cornix', __dir__)

  allowed.each do |dir, ok|
    it "#{dir}/ は #{(ok - [dir.capitalize]).then { |o| o.empty? ? '他のレイヤーに依存しない' : "#{o.join(' / ')} だけに依存する" }}" do
      violations = Dir[File.join(root, dir, '**', '*.rb')].flat_map do |path|
        File.readlines(path, encoding: 'UTF-8').each_with_index.filter_map do |line, i|
          code = line.sub(/#(?!\{).*/, '')
          used = code.scan(/\b(#{layers.join('|')})::/).flatten.uniq - ok
          "#{path.delete_prefix("#{root}/")}:#{i + 1} #{used.join(', ')}" unless used.empty?
        end
      end
      expect(violations).to be_empty
    end
  end
end
