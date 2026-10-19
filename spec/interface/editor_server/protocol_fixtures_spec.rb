# frozen_string_literal: true

require 'spec_helper'

RSpec.describe ProtocolFixtures do
  describe '.mismatches（protocol.md の 8.2 の比べ方）' do
    it 'Hash は期待に書いた項目だけを比べる' do
      expect(described_class.mismatches({ 'a' => 1 }, { 'a' => 1, 'b' => 2 })).to be_empty
      expect(described_class.mismatches({ 'a' => { 'b' => 1 } }, { 'a' => { 'b' => 2, 'c' => 3 } }))
        .to eq(['$.a.b: 1 のはずが 2'])
      expect(described_class.mismatches({ 'a' => nil }, {})).to eq(['$.a: 項目がありません'])
      expect(described_class.mismatches({ 'a' => nil }, { 'a' => 1 })).to eq(['$.a: nil のはずが 1'])
    end

    it '配列は順序と長さごと比べ、要素の Hash は書いた項目だけを比べる' do
      expect(described_class.mismatches([{ 'x' => 1 }, { 'x' => 2 }], [{ 'x' => 1, 'y' => 0 }, { 'x' => 2 }])).to be_empty
      expect(described_class.mismatches([1, 2], [2, 1])).to eq(['$[0]: 1 のはずが 2', '$[1]: 2 のはずが 1'])
      expect(described_class.mismatches([1], [1, 2]).first).to start_with('$: 長さが 1 のはずが 2')
      expect(described_class.mismatches([1], { 'a' => 1 }).first).to start_with('$: 配列のはずが')
    end
  end

  describe '.run' do
    it 'setup の profile を profiles/default に置いて開き（p1）、request への応答を返す' do
      fixture = ProtocolFixtures::Fixture.new(path: 'x.json', data: {
                                                'setup' => { 'profile' => 'test_config' },
                                                'request' => { 'id' => 7, 'method' => 'profile/list' }
                                              })
      outcome = described_class.run(fixture)
      expect(outcome.response).to include('id' => 7, 'result' => include('profiles' => [{ 'dir' => 'profiles/default', 'name' => 'default' }]))
    end

    it '通知の request には応答がない（nil）' do
      fixture = ProtocolFixtures::Fixture.new(path: 'x.json', data: {
                                                'request' => { 'method' => 'profile/close', 'params' => { 'profileId' => 'p9' } }
                                              })
      expect(described_class.run(fixture).response).to be_nil
    end
  end
end
