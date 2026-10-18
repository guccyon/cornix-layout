# frozen_string_literal: true

require 'spec_helper'
require_relative 'planning_images_context'

RSpec.describe Cornix::Planning::MacroList do
  include_context 'planning images'

  it '連続する同じ種類のキー操作と text をまとめ、空の動作を消す' do
    actions = [action(:tap, 4), action(:tap), action(:tap, 5), action(:text, 'a'), action(:text, ''), action(:text, 'b'),
               action(:delay, 10), action(:delay, 20), action(:down, 4), action(:up, 4)]
    expect(described_class.normalize(actions)).to eq(
      [action(:tap, 4, 5), action(:text, 'ab'), action(:delay, 10), action(:delay, 20), action(:down, 4), action(:up, 4)]
    )
  end

  it 'MacroCodec で往復した結果と一致する' do
    codec = Cornix::Mapping::MacroCodec.new
    actions = [action(:tap, 4), action(:tap, 0x0200), action(:text, 'x'), action(:text, 'あ'), action(:delay, 300)]
    expect(codec.decode(codec.encode(actions))).to eq(described_class.normalize(actions))
    expect(described_class.same?(actions, codec.decode(codec.encode(actions)))).to be(true)
  end
end
