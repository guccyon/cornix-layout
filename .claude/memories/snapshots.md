# スナップショット（issue #25）の作業の知見

- 置き場は `Storage::SnapshotStore`（旧 BackupStore）。`<tmp>/snapshots/<日時>-<種類>/layout.vil`。仕様の要点は docs/device.md の「スナップショット」
- issue の未決事項はこう決めた（利用者に確かめる前に PR に書いた判断）:
  - `<tmp>/build/layout.vil` と `<tmp>/layout.vil` は残す（status / apply / MCP の既定の入力・decompile の既定の入力。利用者が置いた layout.vil を読み出しで上書きしないため）。`latest/` は作らない
  - `cornix device backup` は issue の 4 種類に入らないので、種類 `backup` を足した（read の 50 件の削除に巻き込まないため）
  - restore の既定は最新の pre-apply（issue の指定）。そのため「続けて restore すると復元前に戻る」はなくなり、取り消しは pre-restore を名前で渡す
  - 古いものの削除は read と build だけ（種類ごとに 50 件）。書き込みの前の状態は消さない
  - `<tmp>/device_backups/` は種類 legacy として読むだけ。pre-apply がないときの restore の既定にもする
  - MCP のツール名（backup / list_backups / restore_backup）は変えない。list_backups に kind を足し、出力を「日時  種類  パス」にした
  - スナップショットに人が読む YAML（profile/）は入れていない（issue では「必要なら」。今後の課題）
- 読み出しのたびにスナップショットが増えるので、spec の `device_environment_context.rb` の `device_vil`（準備の読み出し）は別の root の Environment で読む。
  同じ env で読むと read の件数を数えるテストがずれる
- Interface は Application にしか依存できない（architecture_spec）。CLI / MCP が種類の一覧を使うときは `Application::ListSnapshots::KINDS` を通す
- 同じ秒の番号（-2, -3 …）は種類によらず続けて振る。種類ごとに数えて名前の順で並べると、apply の read → pre-apply が逆に並んだ（レビューの指摘）。mtime は Linux の粒度が粗く同じ値になりうるので使わない
- 一覧の絞り込みの種類の誤りは ConfigError（利用者の入力）、save の種類の誤りは ArgumentError（コードの誤り）
