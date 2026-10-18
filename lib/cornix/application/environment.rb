# frozen_string_literal: true

module Cornix
  module Application
    # ユースケースが使う部品（場所と、必要になったときに初めて作る部品）を持つ。
    #
    #   env = Environment.new                                  # root は Cornix::ROOT
    #   env.open_device { |session| ... }                      # ブロックの戻り値を返す
    #   Environment.new(root: dir, device_opener: ->(&blk) { blk.call(Device::Session.new(fake, definition: ...)) })
    #
    # device_opener は ->(&blk) { ... } で、Device::Session を blk に渡すもの（閉じるのは opener の責務）。
    # 既定は Device::Session.open（HID ブリッジを開く）。テストでは FakeRmkDevice を使う opener を渡す。
    # claude は rename の提案を作る Claude CLI（#available? と #run(prompt) → [成功, 出力]）。テストでは差し替える。
    #
    # 場所の既定値: config_dir = root/config、layout_path = root/layout.vil、tmp_dir = root/tmp、
    # decompile_input = root/tmp/layout.vil、backup_dir = root/tmp/device_backups。
    # position_map のテンプレートは root によらず lib/cornix/position_map.yaml
    class Environment
      POSITION_MAP_TEMPLATE = File.join(Cornix::ROOT, 'lib', 'cornix', 'position_map.yaml')

      attr_reader :root, :config_dir, :layout_path, :backup_dir, :tmp_dir, :decompile_input, :position_map_template

      def initialize(root: Cornix::ROOT, config_dir: nil, layout_path: nil, backup_dir: nil, device_opener: nil,
                     claude: nil, position_map_template: POSITION_MAP_TEMPLATE)
        @root = root.to_s
        @config_dir = (config_dir || File.join(@root, 'config')).to_s
        @layout_path = (layout_path || File.join(@root, 'layout.vil')).to_s
        @tmp_dir = File.join(@root, 'tmp')
        @decompile_input = File.join(@tmp_dir, 'layout.vil')
        @backup_dir = (backup_dir || File.join(@tmp_dir, 'device_backups')).to_s
        @position_map_template = position_map_template.to_s
        @claude = claude
        @device_opener = device_opener || lambda do |&blk|
          Device::Session.open(catalog: catalog, settings_catalog: settings_catalog, &blk)
        end
      end

      def catalog = @catalog ||= Mapping::KeycodeCatalog.default
      def settings_catalog = @settings_catalog ||= Mapping::QmkSettingCatalog.default
      def codec = @codec ||= Mapping::KeycodeCodec.new(catalog)
      def notation = @notation ||= Mapping::KeycodeNotation.new(catalog: catalog, codec: codec)
      def vial = @vial ||= Mapping::VialNotation.new(catalog: catalog, codec: codec)
      def macro_codec = @macro_codec ||= Mapping::MacroCodec.new
      def mapper = @mapper ||= Mapping::ProfileMapper.new(codec: codec)
      def vil_file = @vil_file ||= Storage::VilFile.new(vial: vial)
      def backup_store = @backup_store ||= Storage::BackupStore.new(backup_dir, vil_file: vil_file)
      def repository = @repository ||= Storage::ConfigRepository.new(config_dir, notation: notation, settings_catalog: settings_catalog)
      def config_editor = @config_editor ||= Storage::ConfigEditor.new(config_dir)
      def decompile_lock = Storage::DecompileLock.new(config_dir)
      def claude = @claude ||= ClaudeCli.new

      # Planning::Change を人が読む文字列にする（キーコードは .vil と同じ Vial の表記）
      def describer
        @describer ||= Device::ChangeDescriber.new(catalog: catalog, formatter: vial.method(:format_code))
      end

      # デバイスを開いて { |session| } を呼び、ブロックの戻り値を返す
      def open_device(&block)
        raise ArgumentError, 'open_device にはブロックが必要です' unless block

        result = nil
        @device_opener.call { |session, *| result = block.call(session) }
        result
      end
    end
  end
end
