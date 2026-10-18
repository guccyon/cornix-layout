# frozen_string_literal: true

require 'tmpdir'
require 'json'
require_relative '../device/fake_rmk_device'

# FakeRmkDevice を開く device_opener と、一時ディレクトリを root にした Environment
RSpec.shared_context 'device environment' do
  let(:device) { FakeRmkDevice.new }
  let(:opens) { [] }
  let(:opener) do
    lambda do |&block|
      opens << :open
      block.call(Cornix::Device::Session.new(device, definition: FakeRmkDevice::DEFINITION))
    end
  end
  let(:env) { Cornix::Application::Environment.new(root: @root, device_opener: opener) }

  around do |example|
    Dir.mktmpdir { |dir| (@root = dir) && example.run }
  end

  # 現在のデバイスの .vil（Hash）
  def device_vil = JSON.parse(Cornix::Application::DeviceRead.new(env).call.vil)

  # 現在のデバイスの .vil を変えて path に書く
  def write_vil(path = env.layout_path)
    vil = device_vil
    yield vil
    File.write(path, JSON.generate(vil))
    path
  end
end
