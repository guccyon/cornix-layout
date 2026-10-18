# frozen_string_literal: true

require 'spec_helper'
require_relative 'support/domain_factories'

RSpec.describe Cornix::Domain::TapDance do
  include DomainFactories

  it '番号・名前・4 つの動作・tapping_term を持つ' do
    td = build_tap_dance(index: 4, name: 'Tab Escape', on_tap: basic(0x2B), on_hold: mo(1), tapping_term: 180)
    expect(td.index).to eq(4)
    expect(td.name).to eq('Tab Escape')
    expect(td.actions).to eq(on_tap: basic(0x2B), on_hold: mo(1), on_double_tap: k::NO_KEY, on_tap_hold: k::NO_KEY)
    expect(td.tapping_term).to eq(180)
    expect(td.description).to be_nil
    expect(td.to_s).to eq('TapDance(4: Tab Escape)')
  end

  it '番号は TD(0)〜TD(255) の範囲' do
    expect(build_tap_dance(index: 255).index).to eq(255)
    expect { build_tap_dance(index: 256) }.to raise_error(Cornix::InvalidValue, /タップダンスの番号/)
    expect { build_tap_dance(index: nil) }.to raise_error(Cornix::InvalidValue)
  end

  it '名前は空でない文字列' do
    expect { build_tap_dance(name: '') }.to raise_error(Cornix::InvalidValue, /タップダンスの名前/)
  end

  it '動作はどれもキーコード（使わない動作は NO_KEY）' do
    expect { build_tap_dance(on_tap: nil) }.to raise_error(Cornix::InvalidValue, /on_tap/)
    expect { build_tap_dance(on_hold: 'KC_NO') }.to raise_error(Cornix::InvalidValue, /on_hold/)
    expect { build_tap_dance(on_double_tap: 0) }.to raise_error(Cornix::InvalidValue, /on_double_tap/)
    expect { build_tap_dance(on_tap_hold: -1) }.to raise_error(Cornix::InvalidValue, /on_tap_hold/)
  end

  it 'tapping_term は 0〜65535 の整数' do
    expect(build_tap_dance(tapping_term: 0).tapping_term).to eq(0)
    expect(build_tap_dance(tapping_term: 65_535).tapping_term).to eq(65_535)
    expect { build_tap_dance(tapping_term: 65_536) }.to raise_error(Cornix::InvalidValue, /tapping_term/)
    expect { build_tap_dance(tapping_term: nil) }.to raise_error(Cornix::InvalidValue)
    expect { build_tap_dance(tapping_term: '200') }.to raise_error(Cornix::InvalidValue)
  end

  it '動作ごとに注記を持てる' do
    td = build_tap_dance(notes: { on_tap: 'A を送る' })
    expect(td.note(:on_tap)).to eq('A を送る')
    expect(td.note(:on_hold)).to be_nil
    expect { build_tap_dance(notes: { tapping_term: 'x' }) }.to raise_error(Cornix::InvalidValue, /タップダンスの注記/)
  end
end
