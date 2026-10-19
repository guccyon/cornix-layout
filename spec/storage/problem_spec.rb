# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Cornix::Storage::Problem do
  it 'location を道筋にする' do
    expect(described_class.new(file: 'macros/00_a.yaml', location: 'sequence[1].keys[0]', message: 'x').path)
      .to eq(['sequence', 1, 'keys', 0])
    expect(described_class.new(file: 'layers/0_a.yaml', location: 'mapping.left_hand.row0.tab.key', message: 'x').path)
      .to eq(%w[mapping left_hand row0 tab key])
    expect(described_class.new(file: 'metadata.yaml', message: 'ファイルがありません').path).to eq([])
  end

  it '文字列から戻すので、キーに . や [ ] を含むと別の道筋になる（shortcuts.yaml の名前。H は道筋を信じない）' do
    expect(described_class.new(file: 'shortcuts.yaml', location: 'shortcuts.Ver.2', message: 'x').path)
      .to eq(%w[shortcuts Ver 2])
  end
end
