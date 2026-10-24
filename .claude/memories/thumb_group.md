# 親指のグループ thumb（旧名 thumb_keys）

2026-10-24 に `thumb_keys` を `thumb` に改名し、テンプレートを `data/position_map.yaml` に移した（親指の名前は l_left / l_mid / l_right、r_left / r_mid / r_right）。

- 旧名の読み替えは `Storage::Schema::HandGroups` だけ。Domain（`PositionMap::GROUPS`）・Profile・意味検証のパスは `thumb` だけを使う。`Domain::PositionMap.from_h` に thumb_keys の Hash を渡すと「thumb がありません」になる（spec で fixture を読むときは `ConfigRepository.read_position_map` を使う）
- エディタの Address と validate の場所はファイルの中の道筋なので、ファイルごとに書いているキー（`HandGroups.written_key`）を使う。Snapshot / PlanEdits::Targets / RenamePosition / DiagnosticLocator の 4 か所。group を道筋に直接入れる場所を足すときは同じようにする
- spec/fixtures の test_config・authors_config・authors_decompiled_config と protocol の fixture のファイルの中身は旧名のまま（後方互換の確認を兼ねる。test_config を移すと protocol の fixture と偽のサーバーまで直すことになる）。新しい名前は spec の中でファイルを書き換えて確かめている
- VS Code 拡張の偽のサーバー（test/fake-server/fixtures.ts）の positionMap の group は旧名のまま（前の版のサーバーの形）。拡張の `groupLabel` は両方を親指にする
