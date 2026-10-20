# frozen_string_literal: true

require 'spec_helper'

RSpec.describe Cornix::Interface::EditorServer::Handler do
  after { %w[test/echo test/note test/other].each { |name| described_class.unregister(name) } }

  it 'サブクラスで rpc / notification を書くと registry に載る（振り分けの表は編集しない）' do
    echo = Class.new(described_class) { rpc 'test/echo' }
    note = Class.new(described_class) { notification 'test/note' }
    expect(described_class.registry).to include('test/echo' => echo, 'test/note' => note)
    expect(echo.method_name).to eq('test/echo')
    expect(echo.notification?).to be(false)
    expect(note.notification?).to be(true)
    expect(described_class.registry).to be_frozen
    expect(described_class.fetch('test/echo')).to eq(echo)
    expect(described_class.fetch('test/none')).to be_nil
  end

  it 'unregister で登録を外せる（テストの片付け用）' do
    echo = Class.new(described_class) { rpc 'test/echo' }
    expect(described_class.unregister('test/echo')).to eq(echo)
    expect(described_class.fetch('test/echo')).to be_nil
  end

  it '1 つのクラスで 2 つのメソッドを受け持とうとすると ArgumentError（古い名前を残さない）' do
    expect do
      Class.new(described_class) do
        rpc 'test/echo'
        rpc 'test/other'
      end
    end.to raise_error(ArgumentError, /1 クラスに 1 メソッド/)
    expect(described_class.fetch('test/other')).to be_nil
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
        def call(params, _context)
          return param(params['change'] || {}, 'address', Hash, field: 'changes[0].address') if params.key?('change')

          [param(params, 'dir', String), param(params, 'limit', Integer, optional: true)]
        end
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

    it 'field: で入れ子の値の道筋を data.field にできる' do
      expect(handler.call({ 'change' => { 'address' => { 'file' => 'a' } } }, nil)).to eq('file' => 'a')
      error = rpc_error({ 'change' => { 'address' => 'x' } })
      expect([error.data, error.message]).to eq([{ field: 'changes[0].address' }, 'params の changes[0].address の形が違います'])
    end
  end
end
