# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Cornix::Storage::BackupStore do
  around do |example|
    Dir.mktmpdir { |dir| @tmp = dir and example.run }
  end

  let(:dir) { File.join(@tmp, 'device_backups') }
  let(:store) { described_class.new(dir) }
  let(:image) { Cornix::Storage::VilFile.new.read(File.expand_path('../fixtures/layout.vil', __dir__)) }

  it '既定の置き場は旧 Device::Keyboard::BACKUP_DIR と同じ tmp/device_backups' do
    expect(described_class::DEFAULT_DIR).to eq(File.join(Cornix::ROOT, 'tmp', 'device_backups'))
    expect(described_class.new.dir).to eq(described_class::DEFAULT_DIR)
  end

  it '#save は日時の名前で .vil を書いてパスを返す（ディレクトリがなければ作る）' do
    path = store.save(image, time: Time.new(2026, 10, 18, 9, 5, 7))
    expect(path).to eq(File.join(dir, '20261018-090507.vil'))
    expect(Cornix::Storage::VilFile.new.read(path)).to eq(image)
  end

  it '#list は新しい順、#latest は最新（なければ nil）' do
    expect(store.list).to eq([])
    expect(store.latest).to be_nil
    older = store.save(image, time: Time.new(2026, 1, 2, 3, 4, 5))
    newer = store.save(image, time: Time.new(2026, 10, 1, 0, 0, 0))
    File.write(File.join(dir, 'note.txt'), 'x')
    expect(store.list).to eq([newer, older])
    expect(store.latest).to eq(newer)
  end

  describe '#resolve / #load' do
    let!(:older) { store.save(image, time: Time.new(2026, 1, 2, 3, 4, 5)) }
    let!(:newer) { store.save(image, time: Time.new(2026, 10, 1, 0, 0, 0)) }

    it '省略すると最新' do
      expect(store.resolve).to eq(newer)
      expect(store.load).to eq(image)
    end

    it 'パス・ファイル名・拡張子なしの名前で指定できる' do
      expect(store.resolve(older)).to eq(older)
      expect(store.resolve('20260102-030405.vil')).to eq(older)
      expect(store.resolve('20260102-030405')).to eq(older)
      expect(store.load('20260102-030405')).to eq(image)
    end

    it '見つからなければ ConfigError' do
      expect { store.resolve('nope') }.to raise_error(Cornix::ConfigError, /バックアップが見つかりません/)
    end

    it 'バックアップが 1 つもなければ ConfigError' do
      empty = described_class.new(File.join(@tmp, 'empty'))
      expect { empty.load }.to raise_error(Cornix::ConfigError, /バックアップがありません/)
    end
  end
end
