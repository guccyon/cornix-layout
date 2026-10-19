# frozen_string_literal: true

require 'spec_helper'
require 'stringio'

RSpec.describe Cornix::Interface::EditorServer::Framing do
  def frame(body) = "Content-Length: #{body.bytesize}\r\n\r\n#{body}"

  def io(text) = StringIO.new(text.dup.force_encoding(Encoding::BINARY))

  it 'Content-Length の枠で 1 メッセージずつ読み、EOF で nil を返す' do
    input = io(frame('{"a":1}') + frame('{"b":"日本語"}'))
    expect(described_class.read(input)).to eq('a' => 1)
    expect(described_class.read(input)).to eq('b' => '日本語')
    expect(described_class.read(input)).to be_nil
  end

  it 'Content-Length はバイト数で、ほかのヘッダーと名前の大文字小文字は気にしない' do
    body = '{"text":"あ"}'
    input = io("content-length: #{body.bytesize}\r\nContent-Type: application/vscode-jsonrpc; charset=utf-8\r\n\r\n#{body}")
    expect(described_class.read(input)).to eq('text' => 'あ')
  end

  it '書くときは本文の UTF-8 のバイト数を Content-Length にする' do
    output = StringIO.new(+'').binmode
    described_class.write(output, { text: 'あい' })
    body = '{"text":"あい"}'
    expect(output.string.b).to eq("Content-Length: #{body.bytesize}\r\n\r\n#{body}".b)
    expect(described_class.read(io(output.string))).to eq('text' => 'あい')
  end

  it 'JSON として読めない本文は ParseError（本文は読み終えているので次を読める）' do
    input = io(frame('{oops') + frame('{"ok":true}'))
    expect { described_class.read(input) }.to raise_error(described_class::ParseError)
    expect(described_class.read(input)).to eq('ok' => true)
  end

  it 'UTF-8 でない本文は ParseError' do
    input = io("Content-Length: 3\r\n\r\n\"\xFF\"".b)
    expect { described_class.read(input) }.to raise_error(described_class::ParseError, /UTF-8/)
  end

  it 'Content-Length がない・数でないヘッダーは HeaderError' do
    expect { described_class.read(io("Content-Type: x\r\n\r\n{}")) }.to raise_error(described_class::HeaderError, /Content-Length/)
    expect { described_class.read(io("Content-Length: abc\r\n\r\n{}")) }.to raise_error(described_class::HeaderError, /数/)
    expect { described_class.read(io('Content-Length: 2')) }.to raise_error(described_class::HeaderError, /途中/)
  end

  it '本文の途中で入力が終われば nil' do
    expect(described_class.read(io("Content-Length: 10\r\n\r\n{}"))).to be_nil
  end
end
