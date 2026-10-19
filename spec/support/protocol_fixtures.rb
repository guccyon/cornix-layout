# frozen_string_literal: true

require 'fileutils'
require 'json'
require 'stringio'
require 'tmpdir'

# 約束の適合テスト（docs/vscode-extension/protocol.md の 8.2）。
# spec/fixtures/protocol/<メソッド>/<名前>.json の「リクエストと期待する応答」の組を読み、cornix serve と同じ枠で
# サーバーに流して確かめる。データを足すだけで spec/interface/editor_server/conformance_spec.rb が拾う。
# データの形（setup・request / raw・response・notifications）と比べ方は protocol.md の 8.2 に書いた（TypeScript 版も同じに読む）
module ProtocolFixtures
  DIR = File.expand_path('../fixtures/protocol', __dir__)
  FIXTURES = File.expand_path('../fixtures', __dir__)
  DEFAULT_PROFILE_DIR = 'profiles/default'

  Fixture = Data.define(:path, :data) do
    def name = path.delete_prefix("#{DIR}/").delete_suffix('.json')
    def description = data['description'] || name
    def setup = data['setup'] || {}
    def request = data['request']
    def raw = data['raw']
    def response = data['response']
    def notifications = data['notifications']
  end

  # サーバーに流した結果。response は request（か raw）への応答（なければ nil）、extra_responses はそのほかの応答（あれば誤り）、
  # notifications はサーバーからの通知、log は標準エラー出力
  Outcome = Data.define(:response, :extra_responses, :notifications, :log)

  module_function

  def all = Dir[File.join(DIR, '**', '*.json')].sort.map { |path| load(path) }

  def load(path) = Fixture.new(path: path, data: JSON.parse(File.read(path, encoding: 'UTF-8')))

  def run(fixture)
    Dir.mktmpdir('cornix-protocol') do |root|
      prepare(root, fixture.setup)
      workbench = Cornix::Application::Editor::Workbench.new(root: root)
      unless fixture.request.nil? ^ fixture.raw.nil?
        raise ArgumentError, "#{fixture.path}: request と raw のどちらか一方を書いてください"
      end

      setup = setup_messages(workbench, fixture.setup)
      body = fixture.raw || JSON.generate(message(fixture.request))
      execute(workbench, setup, body, fixture.request&.dig('id'))
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
    profiles = setup['profiles'] || {}
    if setup['profile']
      raise ArgumentError, "setup.profile と setup.profiles の #{DEFAULT_PROFILE_DIR} が重なっています" if profiles.key?(DEFAULT_PROFILE_DIR)

      copy_profile(root, DEFAULT_PROFILE_DIR, setup['profile'])
    end
    profiles.each { |dir, source| copy_profile(root, dir, source) }
    (setup['files'] || {}).each do |rel, text|
      path = File.join(root, rel)
      FileUtils.mkdir_p(File.dirname(path))
      File.write(path, text)
    end
  end

  def copy_profile(root, dir, source)
    dest = File.join(root, dir)
    raise ArgumentError, "setup の #{dir} がほかの設定ディレクトリと重なっています" if File.exist?(dest)

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
      if Cornix::Interface::EditorServer::Handler.fetch('profile/open')
        list << message('id' => 'setup:open', 'method' => 'profile/open', 'params' => { 'dir' => DEFAULT_PROFILE_DIR })
      else
        workbench.open(DEFAULT_PROFILE_DIR)
      end
    end
    list + (setup['before'] || []).map { |m| message(m) }
  end

  # jsonrpc を省いたら "2.0" を足す。"jsonrpc": null と書いたら項目ごと外す（JSON-RPC の形でないメッセージを書くとき）
  def message(hash)
    full = { 'jsonrpc' => '2.0' }.merge(hash)
    full.delete('jsonrpc') if full['jsonrpc'].nil?
    full
  end

  def execute(workbench, setup, body, request_id)
    framing = Cornix::Interface::EditorServer::Framing
    input = StringIO.new(+'')
    setup.each { |m| framing.write(input, m) }
    input.write("Content-Length: #{body.bytesize}\r\n\r\n", body)
    input.rewind
    output = StringIO.new(+'')
    error = StringIO.new
    Cornix::Interface::EditorServer::Server.new(workbench: workbench, input: input, output: output, error: error).run
    output.rewind
    received = []
    while (m = framing.read(output))
      received << m
    end
    responses = received.reject { |m| m.key?('method') }
    setup_ids = setup.filter_map { |m| m['id'] }
    failed = responses.select { |m| m['id'].to_s.start_with?('setup:') && m.key?('error') }
    raise "setup のリクエストが失敗しました: #{failed.inspect}\n#{error.string}" unless failed.empty?

    own = responses.reject { |m| setup_ids.include?(m['id']) }
    response = request_id.nil? ? own.first : own.find { |m| m['id'] == request_id }
    Outcome.new(response: response, extra_responses: own - [response], notifications: received.select { |m| m.key?('method') },
                log: error.string)
  end
end
