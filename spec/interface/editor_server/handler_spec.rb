# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Cornix::Interface::EditorServer::Handler do
  after { %w[test/echo test/note].each { |name| described_class::REGISTRY.delete(name) } }

  it 'サブクラスで rpc / notification を書くと registry に載る（振り分けの表は編集しない）' do
    echo = Class.new(described_class) { rpc 'test/echo' }
    note = Class.new(described_class) { notification 'test/note' }
    expect(described_class.registry).to include('test/echo' => echo, 'test/note' => note)
    expect(echo.method_name).to eq('test/echo')
    expect(echo.notification?).to be(false)
    expect(note.notification?).to be(true)
    expect(described_class.registry).to be_frozen
  end

  it 'v0.1 の段 1 のメソッドが載っている' do
    expect(described_class.registry.keys)
      .to include('initialize', 'initialized', 'shutdown', 'exit', '$/cancelRequest', 'profile/list', 'profile/close')
  end

  it '同じメソッドを 2 つのクラスで受け持とうとすると ArgumentError' do
    Class.new(described_class) { rpc 'test/echo' }
    expect { Class.new(described_class) { rpc 'test/echo' } }.to raise_error(ArgumentError, %r{test/echo})
  end

  describe '#param' do
    let(:handler) do
      Class.new(described_class) do
        rpc 'test/echo'
        def call(params, _context) = [param(params, 'dir', String), param(params, 'limit', Integer, optional: true)]
      end.new
    end

    def rpc_error(params)
      handler.call(params, nil)
    rescue Cornix::Interface::EditorServer::RpcError => e
      e
    end

    it '型が合えば値を返し、optional なら省ける' do
      expect(handler.call({ 'dir' => 'profiles/a' }, nil)).to eq(['profiles/a', nil])
      expect(handler.call({ 'dir' => 'a', 'limit' => 3 }, nil)).to eq(['a', 3])
    end

    it 'ない・形が違うときは InvalidParams（data.field にその名前）' do
      expect(rpc_error({}).to_h).to include(code: -32_602, data: { field: 'dir' })
      expect(rpc_error({ 'dir' => 1 }).message).to include('dir').and include('形')
      expect(rpc_error({ 'dir' => 'a', 'limit' => 'x' }).data).to eq(field: 'limit')
    end
  end
end
