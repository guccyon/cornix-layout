# frozen_string_literal: true

require 'spec_helper'
require 'tmpdir'

RSpec.describe Cornix::Storage::SnapshotStore do
  around do |example|
    Dir.mktmpdir { |dir| @tmp = dir and example.run }
  end

  let(:dir) { File.join(@tmp, 'snapshots') }
  let(:legacy_dir) { File.join(@tmp, 'device_backups') }
  let(:store) { described_class.new(dir, legacy_dir: legacy_dir) }
  let(:vil_file) { Cornix::Storage::VilFile.new }
  let(:image) { vil_file.read(File.expand_path('../fixtures/layout.vil', __dir__)) }

  def at(*args) = Time.new(*args)

  def write_legacy(name)
    FileUtils.mkdir_p(legacy_dir)
    vil_file.write(image, File.join(legacy_dir, name))
  end

  describe '#save' do
    it '<日時>-<種類>/layout.vil に書いてパスを返す（ディレクトリがなければ作る）' do
      path = store.save(image, kind: 'pre-apply', time: at(2026, 10, 18, 9, 5, 7))
      expect(path).to eq(File.join(dir, '20261018-090507-pre-apply', 'layout.vil'))
      expect(vil_file.read(path)).to eq(image)
    end

    it '同じ秒・同じ種類でも上書きせず -2, -3 を付ける' do
      time = at(2026, 10, 18, 9, 5, 7)
      paths = Array.new(3) { store.save(image, kind: 'read', time: time) }
      expect(paths.map { |p| File.basename(File.dirname(p)) })
        .to eq(%w[20261018-090507-read 20261018-090507-read-2 20261018-090507-read-3])
      expect(store.list.map(&:name)).to eq(%w[20261018-090507-read-3 20261018-090507-read-2 20261018-090507-read])
    end

    it '同じ秒なら種類が違っても番号を続け、一覧は作った順になる' do
      time = at(2026, 1, 1)
      kinds = %w[build read pre-apply read]
      paths = kinds.map { |kind| store.save(image, kind: kind, time: time) }
      expect(paths.map { |p| File.basename(File.dirname(p)) })
        .to eq(%w[20260101-000000-build 20260101-000000-read-2 20260101-000000-pre-apply-3 20260101-000000-read-4])
      expect(store.list.map(&:path)).to eq(paths.reverse)
      expect(store.resolve).to eq(paths[2])
    end

    it '知らない種類は ArgumentError' do
      expect { store.save(image, kind: 'legacy') }.to raise_error(ArgumentError, /知らないスナップショットの種類/)
    end

    it 'read と build は種類ごとに新しい KEEP 件だけ残し、ほかの種類は消さない' do
      stub_const("#{described_class}::KEEP", 2)
      backups = Array.new(3) { |i| store.save(image, kind: 'pre-apply', time: at(2026, 1, 1, 0, 0, i)) }
      reads = Array.new(3) { |i| store.save(image, kind: 'read', time: at(2026, 1, 1, 0, 1, i)) }
      store.save(image, kind: 'build', time: at(2026, 1, 1, 0, 2, 0))
      expect(store.list(kind: 'read').map(&:path)).to eq(reads.drop(1).reverse)
      expect(File.exist?(File.dirname(reads.first))).to be(false)
      expect(store.list(kind: 'pre-apply').map(&:path)).to eq(backups.reverse)
      expect(store.list(kind: 'build').size).to eq(1)
    end
  end

  describe '#list / #latest' do
    it '新しい順（kind で絞り込める）。前の版の device_backups/ は legacy として入る' do
      expect(store.list).to eq([])
      expect(store.latest).to be_nil
      legacy = write_legacy('20260101-000000.vil')
      build = store.save(image, kind: 'build', time: at(2026, 2, 1))
      read = store.save(image, kind: 'read', time: at(2026, 3, 1))
      FileUtils.mkdir_p(File.join(dir, 'notes'))
      File.write(File.join(legacy_dir, 'note.txt'), 'x')

      expect(store.list.map(&:path)).to eq([read, build, legacy])
      expect(store.list.map(&:kind)).to eq(%w[read build legacy])
      expect(store.list(kind: 'legacy').map(&:name)).to eq(['20260101-000000'])
      expect(store.latest&.path).to eq(read)
      expect(store.latest(kind: 'build')&.path).to eq(build)
      expect(store.list.first.to_h)
        .to eq('name' => '20260301-000000-read', 'kind' => 'read', 'time' => at(2026, 3, 1).iso8601, 'path' => read)
    end

    it '知らない種類で絞り込むと ConfigError（利用者の入力の誤り）' do
      expect { store.list(kind: 'nope') }.to raise_error(Cornix::ConfigError, /知らないスナップショットの種類です: nope/)
    end
  end

  describe '#resolve / #load' do
    let!(:older) { store.save(image, kind: 'pre-apply', time: at(2026, 1, 2, 3, 4, 5)) }
    let!(:newer) { store.save(image, kind: 'pre-apply', time: at(2026, 10, 1, 0, 0, 0)) }

    it '省略すると最新の pre-apply（ほかの種類が新しくても）' do
      store.save(image, kind: 'pre-restore', time: at(2026, 11, 1))
      store.save(image, kind: 'read', time: at(2026, 11, 2))
      expect(store.resolve).to eq(newer)
      expect(store.load).to eq(image)
    end

    it '名前・ディレクトリ・layout.vil のパスで指定できる' do
      expect(store.resolve('20260102-030405-pre-apply')).to eq(older)
      expect(store.resolve(File.dirname(older))).to eq(older)
      expect(store.resolve(older)).to eq(older)
      expect(store.load('20260102-030405-pre-apply')).to eq(image)
    end

    it '前の版のバックアップをファイル名（拡張子は省略可）で指定できる' do
      legacy = write_legacy('20250101-000000.vil')
      expect(store.resolve('20250101-000000')).to eq(legacy)
      expect(store.resolve('20250101-000000.vil')).to eq(legacy)
    end

    it '見つからなければ ConfigError' do
      expect { store.resolve('nope') }.to raise_error(Cornix::ConfigError, /スナップショットが見つかりません/)
    end
  end

  describe '#resolve（省略時の戻し先）' do
    it 'pre-apply がなければ前の版のバックアップの最新' do
      write_legacy('20250101-000000.vil')
      latest = write_legacy('20250201-000000.vil')
      store.save(image, kind: 'read')
      expect(store.resolve).to eq(latest)
    end

    it 'pre-apply も前の版のバックアップもなければ ConfigError' do
      store.save(image, kind: 'backup')
      expect { store.resolve }.to raise_error(Cornix::ConfigError, /戻す元のスナップショット.*cornix snapshots で一覧/)
    end
  end
end
