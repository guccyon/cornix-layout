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
    class Environment
      attr_reader :root, :config_dir, :layout_path, :backup_dir

      def initialize(root: Cornix::ROOT, config_dir: nil, layout_path: nil, backup_dir: nil, device_opener: nil)
        @root = root.to_s
        @config_dir = (config_dir || File.join(@root, 'config')).to_s
        @layout_path = (layout_path || File.join(@root, 'layout.vil')).to_s
        @backup_dir = (backup_dir || File.join(@root, 'tmp', 'device_backups')).to_s
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
