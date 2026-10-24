# frozen_string_literal: true

require 'spec_helper'
require_relative '../../support/device_protocol_fixtures'

# device のサーバーの約束の適合テスト（docs/vscode-extension/protocol.md の 14.10）。
# spec/fixtures/protocol/device/**/*.json を、偽の実機（FakeCornixDevice）をつないだ cornix serve --device に流す。
# 書き方は spec/support/device_protocol_fixtures.rb
RSpec.describe '約束の適合テスト（spec/fixtures/protocol/device）' do
  DeviceProtocolFixtures.all.group_by { |f| File.dirname(f.name) }.each do |group, fixtures|
    describe group do
      fixtures.each do |fixture|
        it "#{File.basename(fixture.name)}: #{fixture.description}" do
          outcome = DeviceProtocolFixtures.run(fixture)
          problems = []
          if fixture.response
            problems += outcome.response ? ProtocolFixtures.mismatches(fixture.response, outcome.response) : ['応答がありません']
          elsif outcome.response
            problems << "応答がないはずが #{outcome.response.inspect}"
          end
          problems += outcome.extra_responses.map { |m| "ほかの応答があります: #{m.inspect}" }
          problems += ProtocolFixtures.mismatches(fixture.notifications, outcome.notifications, '$notifications') if fixture.notifications
          expect(problems).to be_empty, "#{fixture.path}\n#{problems.join("\n")}\n応答: #{outcome.response.inspect}\nログ: #{outcome.log}"
        end
      end
    end
  end

  it 'データが 1 件以上ある' do
    expect(DeviceProtocolFixtures.all).not_to be_empty
  end
end
