# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'stringio'
require 'tmpdir'

# 約束の適合テスト（docs/vscode-extension/protocol.md の 8.2）。
# spec/fixtures/protocol/<メソッド>/<名前>.json の「リクエストと期待する応答」の組を読み、cornix serve と同じ枠で
# サーバーに流して確かめる。データを足すだけで spec/interface/editor_server/conformance_spec.rb が拾う。
#
# データの形（setup の項目はどれも省ける）:
#   {
#     "description": "何を確かめるか（省けばファイル名）",
#     "setup": {
#       "profile": "test_config",                       # spec/fixtures/<名前> を <ワークスペース>/profiles/default に置き、開いておく（id は "p1"）
#       "open": false,                                  # profile を開かずに置くだけにする（profile/open 自体を確かめるとき）
#       "profiles": { "profiles/ipad": "test_config", "config": null },   # ほかの設定ディレクトリ（null なら空のディレクトリ）
#       "files": { ".cornix.yml": "profile: ipad\n" },  # ワークスペースに書くファイル（ワークスペースからの相対パス）
#       "initialize": false,                            # initialize / initialized を送らない（既定では先に送る）
#       "before": [ { "id": "b1", "method": "shutdown" } ]   # request の前に送るメッセージ（応答は確かめない）
#     },
#     "request": { "id": 1, "method": "profile/list", "params": {} },   # jsonrpc は省ける。id がなければ通知
#     "response": { "result": { "default": "profiles/default" } },      # request への応答（通知なら書かない）
#     "notifications": [ { "method": "profile/didChange", "params": { "profileId": "p1" } } ]   # サーバーからの通知（書けば確かめる）
#   }
#
# 比べ方: Hash は期待に書いた項目だけを比べる（版の文字列など、書かない項目は比べない）。配列は順序と長さごと比べる。
# ほかの値は == で比べる（null も書けば比べる）
module ProtocolFixtures
  DIR = File.expand_path('../fixtures/protocol', __dir__)
  FIXTURES = File.expand_path('../fixtures', __dir__)
  DEFAULT_PROFILE_DIR = 'profiles/default'

  Fixture = Data.define(:path, :data) do
    def name = path.delete_prefix("#{DIR}/").delete_suffix('.json')
    def description = data['description'] || name
    def setup = data['setup'] || {}
    def request = data.fetch('request')
    def response = data['response']
    def notifications = data['notifications']
  end

  # サーバーに流した結果。response は request への応答（なければ nil）、notifications はサーバーからの通知、log は標準エラー出力
  Outcome = Data.define(:response, :notifications, :log)

  module_function

  def all = Dir[File.join(DIR, '**', '*.json')].sort.map { |path| load(path) }

  def load(path) = Fixture.new(path: path, data: JSON.parse(File.read(path, encoding: 'UTF-8')))

  def run(fixture)
    Dir.mktmpdir('cornix-protocol') do |root|
      prepare(root, fixture.setup)
      workbench = Cornix::Application::Editor::Workbench.new(root: root)
      messages = [*setup_messages(workbench, fixture.setup), message(fixture.request)]
      execute(workbench, messages, fixture.request['id'])
    end
  end

  # 期待（expected）と実際（actual）の違いを「$.result.profiles[0].dir: ...」の形の文字列の配列で返す（なければ空）
  def mismatches(expected, actual, path = '$')
    case expected
    when Hash
      return ["#{path}: オブジェクトのはずが #{actual.inspect}"] unless actual.is_a?(Hash)

      expected.flat_map do |key, value|
        next ["#{path}.#{key}: 項目がありません"] unless actual.key?(key)

        mismatches(value, actual[key], "#{path}.#{key}")
      end
    when Array
      return ["#{path}: 配列のはずが #{actual.inspect}"] unless actual.is_a?(Array)
      return ["#{path}: 長さが #{expected.size} のはずが #{actual.size}（#{actual.inspect}）"] unless actual.size == expected.size

      expected.each_with_index.flat_map { |value, i| mismatches(value, actual[i], "#{path}[#{i}]") }
    else
      expected == actual ? [] : ["#{path}: #{expected.inspect} のはずが #{actual.inspect}"]
    end
  end

  def prepare(root, setup)
    if setup['profile']
      copy_profile(root, DEFAULT_PROFILE_DIR, setup['profile'])
    end
    (setup['profiles'] || {}).each { |dir, source| copy_profile(root, dir, source) }
    (setup['files'] || {}).each do |rel, text|
      path = File.join(root, rel)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, text)
    end
  end

  def copy_profile(root, dir, source)
    dest = File.join(root, dir)
    FileUtils.mkdir_p(File.dirname(dest))
    if source.nil?
      FileUtils.mkdir_p(dest)
    else
      FileUtils.cp_r(File.join(FIXTURES, source), dest)
    end
  end

  # initialize / initialized と、setup の profile を開くリクエストと、before のメッセージ
  def setup_messages(workbench, setup)
    list = []
    unless setup['initialize'] == false
      list << message('id' => 'setup:initialize', 'method' => 'initialize', 'params' => { 'protocolVersion' => '0.1' })
      list << message('method' => 'initialized')
    end
    if setup['profile'] && setup['open'] != false
      # profile/open のハンドラがあればリクエストで開く（知っている版なども作られる）。なければ Workbench で直接開く
      if Cornix::Interface::EditorServer::Handler.registry.key?('profile/open')
        list << message('id' => 'setup:open', 'method' => 'profile/open', 'params' => { 'dir' => DEFAULT_PROFILE_DIR })
      else
        workbench.open(DEFAULT_PROFILE_DIR)
      end
    end
    list + (setup['before'] || []).map { |m| message(m) }
  end

  def message(hash) = { 'jsonrpc' => '2.0' }.merge(hash)

  def execute(workbench, messages, request_id)
    input = StringIO.new
    messages.each { |m| Cornix::Interface::EditorServer::Framing.write(input, m) }
    input.rewind
    output = StringIO.new
    error = StringIO.new
    Cornix::Interface::EditorServer::Server.new(workbench: workbench, input: input, output: output, error: error).run
    output.rewind
    received = []
    while (m = Cornix::Interface::EditorServer::Framing.read(output))
      received << m
    end
    responses = received.select { |m| m.key?('id') && !m.key?('method') }
    failed = responses.select { |m| m['id'].to_s.start_with?('setup:') && m.key?('error') }
    raise "setup のリクエストが失敗しました: #{failed.inspect}\n#{error.string}" unless failed.empty?

    response = request_id.nil? ? nil : responses.find { |m| m['id'] == request_id }
    Outcome.new(response: response, notifications: received.select { |m| m.key?('method') }, log: error.string)
  end
end
