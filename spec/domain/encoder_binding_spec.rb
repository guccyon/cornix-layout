# frozen_string_literal: true

require 'spec_helper'
require_relative 'support/domain_factories'

RSpec.describe Cornix::Domain::EncoderBinding do
  include DomainFactories

  it 'プッシュ・反時計回り・時計回りのキーコードを持つ' do
    binding = described_class.new(push: basic(0x7F), ccw: basic(0x81), cw: basic(0x80))
    expect(binding.push).to eq(basic(0x7F))
    expect(binding.ccw).to eq(basic(0x81))
    expect(binding.cw).to eq(basic(0x80))
    expect(described_class::ACTIONS).to eq(%i[push ccw cw])
  end

  it 'どれもキーコードでなければ InvalidValue（使わない操作は NO_KEY）' do
    expect { described_class.new(push: nil, ccw: k::NO_KEY, cw: k::NO_KEY) }.to raise_error(Cornix::InvalidValue, /プッシュ/)
    expect { described_class.new(push: k::NO_KEY, ccw: 'KC_VOLD', cw: k::NO_KEY) }.to raise_error(Cornix::InvalidValue, /反時計/)
    expect { described_class.new(push: k::NO_KEY, ccw: k::NO_KEY, cw: 0x80) }.to raise_error(Cornix::InvalidValue, /時計回り/)
  end
end
