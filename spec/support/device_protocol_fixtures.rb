# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'tmpdir'
require_relative 'protocol_fixtures'
require_relative '../device/fake_cornix_device'

# device のサーバー（cornix serve --device）の適合テスト（docs/vscode-extension/protocol.md の 14.10）。
# spec/fixtures/protocol/device/<メソッド>/<名前>.json を読み、偽の実機（FakeCornixDevice）をつないだ device のサーバーに流す。
# 形と比べ方は 8.2 と同じ（ProtocolFixtures）。setup に足すもの:
#
#   "allowWrites": true                 --allow-writes を付けたことにする（既定 false）
#   "device": {                         偽の実機の初めの状態
#     "from": "profile",                "profile" は setup.profile（setup.files を書く前）の compile の出力と同じ状態。fixtures のディレクトリ名
#                                       （"authors_config"）ならそれを compile したもの、".vil" で終われば spec/fixtures からのパス
#     "keys": [{ "layer": 0, "row": 0, "col": 1, "value": "KC_A" }],   その上で変えるキー（マトリクスの座標・Vial の表記）
#     "set": [{ "path": ["settings", "7"], "value": 300 }],             その上で変える .vil の値（JSON の道筋）
#     "unavailable": "notConnected",    実機が使えないことにする（platform / bridge / notConnected / timeout）
#     "failWriteAfter": 2,              書き込みのコマンドを 2 回送ったあと応答がなくなる（timeout）
#     "ignoreWrites": true              書き込みに応答するが値が変わらない（読み直しで違いが残る）
#   }
#   "snapshots": { "20261021-101500-pre-apply": "profile" }   置いておくバックアップ（値は device と同じ書き方。
#                                       文字列なら from だけ）。名前が日時だけなら前の版の device_backups/<名前>.vil
#
# fixture の "after"（メッセージの配列）は request の後に送る（読む間の $/cancelRequest を確かめる）。応答は確かめない
module DeviceProtocolFixtures
  DIR = ProtocolFixtures::DEVICE_DIR
  REASONS = { 'platform' => :platform, 'bridge' => :bridge, 'notConnected' => :not_connected, 'timeout' => :timeout }.freeze
  LEGACY_NAME = /\A\d{8}-\d{6}\z/

  # 走らせた結果。outcome は ProtocolFixtures::Outcome、device は終わったときの偽の実機、root はワークスペース（ブロックの中だけ）
  Run = Data.define(:outcome, :device, :root)

  module_function

  def all = Dir[File.join(DIR, '**', '*.json')].sort.map { |path| ProtocolFixtures.load(path) }

  # → ProtocolFixtures::Outcome。ブロックを渡すと、ワークスペースを消す前に Run を渡して呼び、その戻り値を返す
  def run(fixture)
    Dir.mktmpdir('cornix-device-protocol') do |root|
      setup = fixture.setup
      # 実機とバックアップの "profile" は setup.files を書く前のプロファイル
      ProtocolFixtures.prepare(root, setup.except('files'))
      device = FakeCornixDevice.new
      env_factory = lambda do |workspace|
        Cornix::Application::Environment.for(workspace, device_opener: FakeCornixDevice.opener(device))
      end
      prepare_device(root, device, setup['device'] || {})
      place_snapshots(root, setup['snapshots'] || {})
      ProtocolFixtures.prepare(root, { 'files' => setup['files'] })
      unless fixture.request.nil? ^ fixture.raw.nil?
        raise ArgumentError, "#{fixture.path}: request と raw のどちらか一方を書いてください"
      end

      operations = Cornix::Application::Editor::DeviceOperations.new(root: root, env_factory: env_factory)
      body = fixture.raw || JSON.generate(ProtocolFixtures.message(fixture.request))
      after = (fixture.data['after'] || []).map { |m| ProtocolFixtures.message(m) }
      outcome = ProtocolFixtures.execute(setup_messages(setup), body, fixture.request&.dig('id'), after: after) do |input, output, error|
        Cornix::Interface::EditorServer::Server.new(device: operations, allow_writes: setup['allowWrites'] == true,
                                                    input: input, output: output, error: error)
      end
      block_given? ? yield(Run.new(outcome: outcome, device: device, root: root)) : outcome
    end
  end

  def setup_messages(setup)
    list = []
    unless setup['initialize'] == false
      list << ProtocolFixtures.message('id' => 'setup:initialize', 'method' => 'initialize', 'params' => { 'protocolVersion' => '0.5' })
      list << ProtocolFixtures.message('method' => 'initialized')
    end
    list + (setup['before'] || []).map { |m| ProtocolFixtures.message(m) }
  end

  def prepare_device(root, device, spec)
    device.unavailable = REASONS.fetch(spec['unavailable']) if spec['unavailable']
    device.fail_write_after = spec['failWriteAfter']
    device.ignore_writes = spec['ignoreWrites'] == true
    return if spec['from'].nil?

    device.load_image(image(root, spec))
  end

  def place_snapshots(root, snapshots)
    tmp = workspace(root, ProtocolFixtures::DEFAULT_PROFILE_DIR).tmp_dir
    snapshots.each do |name, spec|
      spec = { 'from' => spec } if spec.is_a?(String)
      path = if LEGACY_NAME.match?(name)
               File.join(tmp, 'device_backups', "#{name}.vil")
             else
               File.join(tmp, 'snapshots', name, Cornix::Storage::SnapshotStore::FILE_NAME)
             end
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, JSON.generate(vil(root, spec)))
    end
  end

  # spec（from・keys・set）の状態の Image::DeviceImage
  def image(root, spec)
    helper_env(root).vil_file.parse(JSON.generate(vil(root, spec)))
  end

  # spec の状態の .vil（Hash）
  def vil(root, spec)
    data = JSON.parse(source_vil(root, spec.fetch('from')))
    (spec['keys'] || []).each { |k| data['layout'][k.fetch('layer')][k.fetch('row')][k.fetch('col')] = k.fetch('value') }
    (spec['set'] || []).each do |edit|
      *parents, last = edit.fetch('path')
      container = parents.reduce(data) { |node, key| node.is_a?(Array) ? node.fetch(key) : node.fetch(key.to_s) }
      container[container.is_a?(Array) ? last : last.to_s] = edit.fetch('value')
    end
    data
  end

  # from の .vil の文字列（"profile" は setup の profile、fixtures のディレクトリ名、または spec/fixtures からの .vil のパス）
  def source_vil(root, from)
    return File.read(File.join(ProtocolFixtures::FIXTURES, from), encoding: 'UTF-8') if from.end_with?('.vil')

    dir = from == 'profile' ? File.join(root, ProtocolFixtures::DEFAULT_PROFILE_DIR) : File.join(ProtocolFixtures::FIXTURES, from)
    Dir.mktmpdir('cornix-device-source') do |scratch|
      env = Cornix::Application::Environment.new(root: root, config_dir: dir, tmp_dir: File.join(scratch, 'tmp'))
      result = Cornix::Application::Compile.new(env).call(output: File.join(scratch, 'layout.vil'))
      raise ArgumentError, "#{from} を compile できません: #{result.report.errors.join(', ')}" unless result.compiled?

      File.read(result.path, encoding: 'UTF-8')
    end
  end

  def helper_env(root) = Cornix::Application::Environment.new(root: root)

  def workspace(root, dir)
    Cornix::Application::Workspace.resolve(cwd: root, root: root, config: File.join(root, dir), env: {})
  end
end
