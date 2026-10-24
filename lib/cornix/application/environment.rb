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
    # 場所の既定値: config_dir = root/config、tmp_dir = root/tmp、
    # layout_path = tmp_dir/build/layout.vil（compile の出力。status / apply / device diff などの既定の入力）、
    # decompile_input = tmp_dir/layout.vil（decompile の既定の入力。pull がデバイスから読んだ状態もここに書く）、
    # snapshot_dir = tmp_dir/snapshots（キーボードの状態と compile の出力の履歴。Storage::SnapshotStore）、
    # legacy_backup_dir = tmp_dir/device_backups（前の版のバックアップ。読むだけ）。
    # position_map のテンプレートは root によらず data/position_map.yaml
    #
    # CLI は Environment.for(workspace) で作る（Workspace が設定ディレクトリと tmp/ の場所を決める）
    class Environment
      POSITION_MAP_TEMPLATE = File.join(Cornix::DATA_DIR, 'position_map.yaml')

      attr_reader :root, :config_dir, :layout_path, :snapshot_dir, :legacy_backup_dir, :tmp_dir, :decompile_input, :position_map_template,
                  :workspace

      # tmp のファイルは workspace.tmp_dir の下に置く（<root>/config なら <root>/tmp のまま。
      # ほかの設定ディレクトリでは tmp/profiles/<名前>/ に分け、設定ごとに混ざらないようにする）
      def self.for(workspace, **opts)
        new(root: workspace.root, config_dir: workspace.config_dir, tmp_dir: workspace.tmp_dir, workspace: workspace, **opts)
      end

      def initialize(root: Cornix::ROOT, config_dir: nil, layout_path: nil, snapshot_dir: nil, tmp_dir: nil,
                     device_opener: nil, claude: nil, position_map_template: POSITION_MAP_TEMPLATE, workspace: nil)
        @root = root.to_s
        @workspace = workspace
        @config_dir = (config_dir || File.join(@root, 'config')).to_s
        @tmp_dir = (tmp_dir || File.join(@root, 'tmp')).to_s
        @layout_path = (layout_path || File.join(@tmp_dir, 'build', 'layout.vil')).to_s
        @decompile_input = File.join(@tmp_dir, 'layout.vil')
        @snapshot_dir = (snapshot_dir || File.join(@tmp_dir, 'snapshots')).to_s
        @legacy_backup_dir = File.join(@tmp_dir, 'device_backups')
        @position_map_template = position_map_template.to_s
        @claude = claude
        @device_opener = device_opener || lambda do |&blk|
          Device::Session.open(catalog: catalog, settings_catalog: settings_catalog, &blk)
        end
      end

      def catalog = @catalog ||= Mapping::KeycodeCatalog.default
      def settings_catalog = @settings_catalog ||= Mapping::QmkSettingCatalog.default
      def shortcut_catalog = @shortcut_catalog ||= Mapping::ShortcutCatalog.default
      # Cornix の上限と、対応していないとみられるキー（Profile#diagnostics に渡す）
      def capabilities
        @capabilities ||= Domain::Capabilities::CORNIX.with(unsupported_keycodes: catalog.unsupported_keycodes)
      end
      def codec = @codec ||= Mapping::KeycodeCodec.new(catalog)
      def notation = @notation ||= Mapping::KeycodeNotation.new(catalog: catalog, codec: codec)
      def vial = @vial ||= Mapping::VialNotation.new(catalog: catalog, codec: codec)
      def qmk = @qmk ||= Mapping::QmkNotation.new(catalog: catalog, codec: codec)
      def macro_codec = @macro_codec ||= Mapping::MacroCodec.new
      def mapper = @mapper ||= Mapping::ProfileMapper.new(codec: codec)
      def vil_file = @vil_file ||= Storage::VilFile.new(vial: vial)
      def snapshot_store
        @snapshot_store ||= Storage::SnapshotStore.new(snapshot_dir, legacy_dir: legacy_backup_dir, vil_file: vil_file)
      end
      def repository
        @repository ||= Storage::ConfigRepository.new(config_dir, notation: notation, settings_catalog: settings_catalog,
                                                                  shortcut_catalog: shortcut_catalog)
      end
      def config_editor = @config_editor ||= Storage::ConfigEditor.new(config_dir)
      def decompile_lock = Storage::DecompileLock.new(config_dir)
      def claude = @claude ||= ClaudeCli.new

      # Planning::Change を人が読む文字列にする（キーコードは .vil と同じ Vial の表記。
      # .vil で 16 進になる値（LAG(kc)・M32〜 など Vial Web が読めない名前）は設定ファイルの表記にする）
      def describer
        @describer ||= Device::ChangeDescriber.new(catalog: catalog, formatter: method(:describe_keycode))
      end

      # デバイスを開いて { |session| } を呼び、ブロックの戻り値を返す
      def open_device(&block)
        raise ArgumentError, 'open_device にはブロックが必要です' unless block

        result = nil
        @device_opener.call { |session, *| result = block.call(session) }
        result
      end

      private

      def describe_keycode(code)
        text = vial.format_code(code)
        return text unless text.start_with?('0x')

        named = notation.format(codec.decode(code))
        named.start_with?('0x') ? text : named
      end
    end
  end
end
