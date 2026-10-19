# frozen_string_literal: true

require 'spec_helper'
require_relative 'support/storage_helpers'

RSpec.describe Cornix::Storage::FileSource do
  include StorageHelpers

  describe Cornix::Storage::FileSource::Disk do
    subject(:source) { described_class.new(StorageHelpers::AUTHORS_CONFIG) }

    it 'ディスクのファイルを読む' do
      expect(source.read('layers/0_base.yml')).to eq(File.read(File.join(StorageHelpers::AUTHORS_CONFIG, 'layers/0_base.yml')))
      expect(source.exist?('metadata.yaml')).to be(true)
      expect(source.exist?('shortcuts.yaml')).to be(false)
      expect(source.list(:layers).first).to eq('layers/0_base.yml')
      expect(source.directory?).to be(true)
      expect { source.read('shortcuts.yaml') }.to raise_error(Errno::ENOENT)
    end
  end

  describe Cornix::Storage::FileSource::Overlay do
    let(:disk) { Cornix::Storage::FileSource::Disk.new(StorageHelpers::AUTHORS_CONFIG) }
    subject(:source) do
      described_class.new(disk, { 'layers/0_base.yml' => "edited\n", 'layers/10_new.yaml' => "new\n",
                                  'layers/9_empty.yml' => nil, 'shortcuts.yaml' => "shortcuts: {}\n" })
    end

    it '差し替えた中身を読み、ほかはもとのまま' do
      expect(source.read('layers/0_base.yml')).to eq("edited\n")
      expect(source.read('metadata.yaml')).to eq(disk.read('metadata.yaml'))
      expect(source.exist?('shortcuts.yaml')).to be(true)
      expect(source.dir).to eq(disk.dir)
    end

    it 'nil はファイルがないものとして扱い、足したファイルは一覧に並ぶ' do
      expect(source.exist?('layers/9_empty.yml')).to be(false)
      expect { source.read('layers/9_empty.yml') }.to raise_error(Errno::ENOENT)
      expect(source.list(:layers)).to include('layers/10_new.yaml')
      expect(source.list(:layers)).not_to include('layers/9_empty.yml')
      expect(source.list(:layers)).to eq(source.list(:layers).sort)
      expect(source.list(:macros)).to eq(disk.list(:macros))
    end
  end

  describe Cornix::Storage::FileVersion do
    it 'バイト列そのものの SHA-256' do
      expect(described_class.of('abc')).to eq('sha256:ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad')
      expect(described_class.of("﻿abc")).not_to eq(described_class.of('abc'))
      expect(described_class.of(nil)).to be_nil
    end

    it 'ファイルの版。なければ nil' do
      path = File.join(StorageHelpers::AUTHORS_CONFIG, 'metadata.yaml')
      expect(described_class.read(path)).to eq(described_class.of(File.binread(path)))
      expect(described_class.read(File.join(StorageHelpers::AUTHORS_CONFIG, 'none.yaml'))).to be_nil
    end
  end
end
