# 実装ガイド（Migration Guide）

## 概要

このドキュメントでは、Cornix Compiler/Decompiler リファクタリングの各タスクの実装手順を詳細に記述します。

## 前提条件

- Ruby 2.7+
- RSpec 3.x
- 既存のCornixプロジェクト環境
- Git（ブランチ作業）

---

## Phase 0: 設計ドキュメント作成 ✅

**完了**: このドキュメント含む6ファイルを作成済み

---

## Phase 1: 基盤整備

### Task 1: PositionMap拡張とテスト

**依存**: なし
**所要時間**: 2-3時間
**並列**: 不可（基盤整備）

#### 実装手順

##### Step 1-1: 定数とメソッドシグネチャ追加

```bash
# lib/cornix/position_map.rbを開く
vim lib/cornix/position_map.rb
```

**追加内容**:

```ruby
# lib/cornix/position_map.rb (既存クラスに追加)

class PositionMap
  # === 既存メソッド ===
  # (変更なし)

  # === 新規定数 ===
  THUMB_PHYSICAL_ROW = { left: 3, right: 7 }.freeze
  ENCODER_PUSH_POSITION = {
    left:  { row: 2, col: 6 },
    right: { row: 5, col: 6 }
  }.freeze

  # === 新規メソッド ===

  # 論理行 → 物理行
  def physical_row(hand, logical_row)
    raise ArgumentError, "Invalid hand: #{hand}" unless [:left, :right].include?(hand)
    raise ArgumentError, "Invalid logical_row: #{logical_row}" unless (0..3).include?(logical_row)

    hand == :right ? logical_row + 4 : logical_row
  end

  # 論理列 → 物理列（右手の逆順処理を内包）
  def physical_col(hand, logical_row, logical_col)
    raise ArgumentError, "Invalid hand: #{hand}" unless [:left, :right].include?(hand)
    raise ArgumentError, "Invalid logical_row: #{logical_row}" unless (0..3).include?(logical_row)

    return logical_col if hand == :left

    max_col = (logical_row == 3) ? 2 : 5
    max_col - logical_col
  end

  # 親指キーの物理行
  def thumb_physical_row(hand)
    raise ArgumentError, "Invalid hand: #{hand}" unless THUMB_PHYSICAL_ROW.key?(hand)
    THUMB_PHYSICAL_ROW[hand]
  end

  # 親指キーの物理列
  def thumb_physical_col(hand, thumb_idx)
    raise ArgumentError, "Invalid hand: #{hand}" unless [:left, :right].include?(hand)
    raise ArgumentError, "Invalid thumb_idx: #{thumb_idx}" unless (0..2).include?(thumb_idx)

    hand == :left ? 3 + thumb_idx : 5 - thumb_idx
  end

  # エンコーダープッシュの物理位置
  def encoder_push_position(side)
    raise ArgumentError, "Invalid side: #{side}" unless ENCODER_PUSH_POSITION.key?(side)
    ENCODER_PUSH_POSITION[side]
  end
end
```

##### Step 1-2: テスト追加

```bash
# spec/position_map_spec.rbを開く
vim spec/position_map_spec.rb
```

**追加内容** (~75行):

```ruby
# spec/position_map_spec.rb (既存のdescribeブロックの後に追加)

RSpec.describe Cornix::PositionMap do
  let(:position_map) { Cornix::PositionMap.new('lib/cornix/position_map.yaml') }

  # === 既存テスト ===
  # (変更なし)

  # === 新規テスト ===

  describe '#physical_row' do
    it '左手の論理行を物理行に変換' do
      expect(position_map.physical_row(:left, 0)).to eq(0)
      expect(position_map.physical_row(:left, 1)).to eq(1)
      expect(position_map.physical_row(:left, 2)).to eq(2)
      expect(position_map.physical_row(:left, 3)).to eq(3)
    end

    it '右手の論理行を物理行に変換（+4）' do
      expect(position_map.physical_row(:right, 0)).to eq(4)
      expect(position_map.physical_row(:right, 1)).to eq(5)
      expect(position_map.physical_row(:right, 2)).to eq(6)
      expect(position_map.physical_row(:right, 3)).to eq(7)
    end

    it '無効な hand でエラー' do
      expect { position_map.physical_row(:invalid, 0) }.to raise_error(ArgumentError, /Invalid hand/)
    end

    it '無効な logical_row でエラー' do
      expect { position_map.physical_row(:left, 4) }.to raise_error(ArgumentError, /Invalid logical_row/)
      expect { position_map.physical_row(:left, -1) }.to raise_error(ArgumentError, /Invalid logical_row/)
    end
  end

  describe '#physical_col' do
    context '左手' do
      it '論理列をそのまま物理列に変換' do
        expect(position_map.physical_col(:left, 0, 0)).to eq(0)
        expect(position_map.physical_col(:left, 0, 1)).to eq(1)
        expect(position_map.physical_col(:left, 0, 5)).to eq(5)
        expect(position_map.physical_col(:left, 3, 0)).to eq(0)
        expect(position_map.physical_col(:left, 3, 2)).to eq(2)
      end
    end

    context '右手 row0-2（6要素）' do
      it '論理列を物理列に変換（逆順、max=5）' do
        expect(position_map.physical_col(:right, 0, 0)).to eq(5)  # 5 - 0
        expect(position_map.physical_col(:right, 0, 1)).to eq(4)  # 5 - 1
        expect(position_map.physical_col(:right, 0, 5)).to eq(0)  # 5 - 5
        expect(position_map.physical_col(:right, 1, 2)).to eq(3)  # 5 - 2
        expect(position_map.physical_col(:right, 2, 3)).to eq(2)  # 5 - 3
      end
    end

    context '右手 row3（3要素）' do
      it '論理列を物理列に変換（逆順、max=2）' do
        expect(position_map.physical_col(:right, 3, 0)).to eq(2)  # 2 - 0
        expect(position_map.physical_col(:right, 3, 1)).to eq(1)  # 2 - 1
        expect(position_map.physical_col(:right, 3, 2)).to eq(0)  # 2 - 2
      end
    end
  end

  describe '#thumb_physical_row' do
    it '左手親指キーの物理行を返す' do
      expect(position_map.thumb_physical_row(:left)).to eq(3)
    end

    it '右手親指キーの物理行を返す' do
      expect(position_map.thumb_physical_row(:right)).to eq(7)
    end

    it '無効な hand でエラー' do
      expect { position_map.thumb_physical_row(:invalid) }.to raise_error(ArgumentError)
    end
  end

  describe '#thumb_physical_col' do
    context '左手' do
      it '親指キーの物理列を返す（順序通り）' do
        expect(position_map.thumb_physical_col(:left, 0)).to eq(3)  # 3 + 0
        expect(position_map.thumb_physical_col(:left, 1)).to eq(4)  # 3 + 1
        expect(position_map.thumb_physical_col(:left, 2)).to eq(5)  # 3 + 2
      end
    end

    context '右手' do
      it '親指キーの物理列を返す（逆順）' do
        expect(position_map.thumb_physical_col(:right, 0)).to eq(5)  # 5 - 0
        expect(position_map.thumb_physical_col(:right, 1)).to eq(4)  # 5 - 1
        expect(position_map.thumb_physical_col(:right, 2)).to eq(3)  # 5 - 2
      end
    end

    it '無効な thumb_idx でエラー' do
      expect { position_map.thumb_physical_col(:left, 3) }.to raise_error(ArgumentError, /Invalid thumb_idx/)
      expect { position_map.thumb_physical_col(:left, -1) }.to raise_error(ArgumentError, /Invalid thumb_idx/)
    end
  end

  describe '#encoder_push_position' do
    it '左エンコーダープッシュの物理位置を返す' do
      expect(position_map.encoder_push_position(:left)).to eq({ row: 2, col: 6 })
    end

    it '右エンコーダープッシュの物理位置を返す' do
      expect(position_map.encoder_push_position(:right)).to eq({ row: 5, col: 6 })
    end

    it '無効な side でエラー' do
      expect { position_map.encoder_push_position(:invalid) }.to raise_error(ArgumentError, /Invalid side/)
    end
  end
end
```

##### Step 1-3: テスト実行

```bash
# 新規テストのみ実行
bundle exec rspec spec/position_map_spec.rb

# 期待結果: 全15テスト成功（新規）

# 既存の全テスト実行（既存機能が壊れていないことを確認）
bundle exec rspec

# 期待結果: 全508テスト成功（493既存 + 15新規）
```

##### Step 1-4: 動作確認

```bash
# 既存のcompiler/decompilerが正常動作することを確認
mv config config.backup
ruby bin/decompile
ruby bin/compile
ruby bin/diff_layouts

# 期待結果: FILES ARE IDENTICAL
```

---

## Phase 2: モデル層実装

### Task 2: Metadata & Settings モデル

**依存**: Task 1
**所要時間**: 2-3時間
**並列**: Task 3, 4, 5, 6 と並列可能

#### 実装手順

##### Step 2-1: ディレクトリ作成

```bash
mkdir -p lib/cornix/models
mkdir -p spec/models
```

##### Step 2-2: Metadata モデル実装

```bash
vim lib/cornix/models/metadata.rb
```

**実装内容** (~80行): [models.md の Metadata クラス定義を参照]

##### Step 2-3: Settings モデル実装

```bash
vim lib/cornix/models/settings.rb
```

**実装内容** (~60行): [models.md の Settings クラス定義を参照]

##### Step 2-4: テスト作成

```bash
vim spec/models/metadata_spec.rb
```

**テスト内容** (~100行, 15テスト):
- `from_qmk` / `to_qmk` の往復変換
- `from_yaml_hash` / `to_yaml_hash` の往復変換
- 必須フィールドのバリデーション
- エッジケース（nil, 空文字列）

```bash
vim spec/models/settings_spec.rb
```

**テスト内容** (~80行, 12テスト):
- 同様の往復変換テスト

##### Step 2-5: テスト実行

```bash
bundle exec rspec spec/models/metadata_spec.rb
bundle exec rspec spec/models/settings_spec.rb

# 期待結果: 計27テスト成功
```

---

### Task 3: Macro & MacroCollection モデル

**依存**: Task 1
**所要時間**: 3-4時間
**並列**: Task 2, 4, 5, 6 と並列可能

#### 実装手順

（Task 2と同様のパターン）

##### Step 3-1: Macro モデル実装

```bash
vim lib/cornix/models/macro.rb
```

**実装内容** (~100行): [models.md の Macro クラス定義を参照]

##### Step 3-2: MacroCollection モデル実装

```bash
vim lib/cornix/models/macro_collection.rb
```

**実装内容** (~80行): [models.md の MacroCollection クラス定義を参照]

##### Step 3-3: テスト作成

```bash
vim spec/models/macro_spec.rb          # ~120行, 18テスト
vim spec/models/macro_collection_spec.rb  # ~100行, 12テスト
```

##### Step 3-4: テスト実行

```bash
bundle exec rspec spec/models/macro_spec.rb
bundle exec rspec spec/models/macro_collection_spec.rb

# 期待結果: 計30テスト成功
```

---

### Task 4, 5: TapDance & Combo モデル

（Task 3と同様のパターンで実装）

---

### Task 6: Layer & LayerCollection モデル

**依存**: Task 1
**所要時間**: 8-10時間
**並列**: Task 2-5 と並列可能（ただし最も複雑なため専任推奨）

#### 実装手順

##### Step 6-1: Layer モデル実装（インナークラス含む）

```bash
vim lib/cornix/models/layer.rb
```

**実装内容** (~350行, インナークラス含む): [models.md の Layer クラス定義を参照]

**重要**: インナークラス（KeyMapping, LeftHandMapping, RightHandMapping, EncoderMapping）を含む

##### Step 6-2: LayerCollection モデル実装

```bash
vim lib/cornix/models/layer_collection.rb
```

**実装内容** (~100行): [models.md の LayerCollection クラス定義を参照]

##### Step 6-3: Fixture作成

```bash
mkdir -p spec/fixtures
vim spec/fixtures/minimal_layout.json  # 最小構成のlayout.vil
vim spec/fixtures/minimal_layer.yaml   # 最小構成のレイヤーYAML
```

##### Step 6-4: テスト作成

```bash
vim spec/models/layer_spec.rb              # ~250行, 35テスト
vim spec/models/layer_collection_spec.rb   # ~100行, 12テスト
```

**テスト内容**:
- Layer の from_qmk / to_qmk 往復
- Layer の from_yaml_hash / to_yaml_hash 往復
- LeftHandMapping / RightHandMapping の構造検証
- EncoderMapping の検証
- KeyMapping の生成テスト
- LayerCollection のサイズ検証
- **PositionMap 統合テスト（物理座標変換）**

##### Step 6-5: テスト実行

```bash
bundle exec rspec spec/models/layer_spec.rb
bundle exec rspec spec/models/layer_collection_spec.rb

# 期待結果: 計47テスト成功
```

---

### Task 7: VialConfig モデル

**依存**: Task 2, 3, 4, 5, 6
**所要時間**: 3-4時間
**並列**: 不可（全モデルが完成後）

#### 実装手順

##### Step 7-1: VialConfig モデル実装

```bash
vim lib/cornix/models/vial_config.rb
```

**実装内容** (~150行): [models.md の VialConfig クラス定義を参照]

##### Step 7-2: テスト作成

```bash
vim spec/models/vial_config_spec.rb  # ~150行, 20テスト
```

**テスト内容**:
- VialConfig の from_qmk / to_qmk 往復
- VialConfig の from_yaml_hashes / to_yaml_hashes 往復
- 各コレクションの集約テスト

##### Step 7-3: テスト実行

```bash
bundle exec rspec spec/models/vial_config_spec.rb

# 期待結果: 20テスト成功
```

---

## Phase 3: Loader/Writer 実装

### Task 8-11: Loader/Writer 実装

**依存**: Task 7
**所要時間**: 6-8時間（並列実行）
**並列**: 4タスク並列可能

#### 実装手順

##### Step 8: VialLoader 実装

```bash
mkdir -p lib/cornix/loaders
vim lib/cornix/loaders/vial_loader.rb
```

**実装内容** (~100行):
```ruby
module Cornix
  module Loaders
    class VialLoader
      def initialize(vil_path)
        @vil_path = vil_path
      end

      def load(position_map:, keycode_converter:)
        json_str = File.read(@vil_path)
        qmk_hash = JSON.parse(json_str)

        Models::VialConfig.from_qmk(
          qmk_hash,
          position_map: position_map,
          keycode_converter: keycode_converter
        )
      end
    end
  end
end
```

**テスト作成**:
```bash
vim spec/loaders/vial_loader_spec.rb
```

##### Step 9: YamlLoader 実装

```bash
vim lib/cornix/loaders/yaml_loader.rb
```

**実装内容** (~120行):
```ruby
module Cornix
  module Loaders
    class YamlLoader
      def initialize(config_dir)
        @config_dir = config_dir
      end

      def load(position_map:, keycode_converter:, reference_converter:)
        metadata_hash = YAML.load_file("#{@config_dir}/metadata.yaml")
        settings_hash = YAML.load_file("#{@config_dir}/settings/qmk_settings.yaml")

        layers_hashes = Dir.glob("#{@config_dir}/layers/*.yaml").sort.map { |f|
          YAML.load_file(f)
        }

        # ... macros, tap_dances, combos も同様

        Models::VialConfig.from_yaml_hashes(
          metadata_hash: metadata_hash,
          settings_hash: settings_hash,
          layers_hashes: layers_hashes,
          macros_hashes: macros_hashes,
          tap_dances_hashes: tap_dances_hashes,
          combos_hashes: combos_hashes,
          position_map: position_map,
          keycode_converter: keycode_converter,
          reference_converter: reference_converter
        )
      end
    end
  end
end
```

##### Step 10: VialWriter 実装

```bash
mkdir -p lib/cornix/writers
vim lib/cornix/writers/vial_writer.rb
```

**実装内容** (~60行):
```ruby
module Cornix
  module Writers
    class VialWriter
      def write(qmk_hash, output_path)
        json_str = JSON.pretty_generate(qmk_hash)
        File.write(output_path, json_str)
      end
    end
  end
end
```

##### Step 11: YamlWriter 実装

```bash
vim lib/cornix/writers/yaml_writer.rb
vim lib/cornix/writers/writer_helpers.rb  # minimize_quotesを移動
```

**実装内容** (~150行):
```ruby
module Cornix
  module Writers
    class YamlWriter
      def initialize(output_dir)
        @output_dir = output_dir
      end

      def write(yaml_hashes)
        write_yaml_file("#{@output_dir}/metadata.yaml", yaml_hashes[:metadata])
        write_yaml_file("#{@output_dir}/settings/qmk_settings.yaml", yaml_hashes[:settings])

        yaml_hashes[:layers].each_with_index do |layer_hash, idx|
          filename = "#{idx}_#{layer_hash['name'].downcase.tr(' ', '_')}.yaml"
          write_yaml_file("#{@output_dir}/layers/#{filename}", layer_hash)
        end

        # ... macros, tap_dances, combos も同様
      end

      private

      def write_yaml_file(path, hash)
        FileUtils.mkdir_p(File.dirname(path))
        yaml_str = YAML.dump(hash)
        yaml_str = minimize_quotes(yaml_str)  # writer_helpersから
        File.write(path, yaml_str)
      end

      def minimize_quotes(yaml_str)
        # 既存のdecompiler.rbから移動
        # ...
      end
    end
  end
end
```

##### テスト実行

```bash
bundle exec rspec spec/loaders/
bundle exec rspec spec/writers/

# 期待結果: 計40テスト成功（各10テスト）
```

---

## Phase 4: Converter/Validator 実装

### Task 12-14: Converter/Validator 実装

**依存**: Task 7
**所要時間**: 5-6時間（並列実行）
**並列**: 3タスク並列可能

#### 実装手順

##### Step 12: KeycodeConverter 実装

```bash
mkdir -p lib/cornix/converters
vim lib/cornix/converters/keycode_converter.rb
```

**実装内容**:
- 既存 `lib/cornix/keycode_resolver.rb` の機能を移行
- メソッド名は同じ（`resolve`, `reverse_resolve`）

```ruby
module Cornix
  module Converters
    class KeycodeConverter
      # 既存 KeycodeResolver の実装をコピー＆移行
      # ...
    end
  end
end
```

**テスト移行**:
```bash
cp spec/keycode_resolver_spec.rb spec/converters/keycode_converter_spec.rb
# module名を修正
```

##### Step 13: ReferenceConverter 実装

```bash
vim lib/cornix/converters/reference_converter.rb
```

**実装内容**:
- 既存 `lib/cornix/reference_resolver.rb` の機能を移行

**テスト移行**:
```bash
cp spec/reference_resolver_spec.rb spec/converters/reference_converter_spec.rb
```

##### Step 14: ModelValidator 実装

```bash
mkdir -p lib/cornix/validators
vim lib/cornix/validators/model_validator.rb
```

**実装内容**:
- 既存 `lib/cornix/validator.rb` の機能を移行

**テスト移行**:
```bash
cp spec/validator_spec.rb spec/validators/model_validator_spec.rb
```

##### テスト実行

```bash
bundle exec rspec spec/converters/
bundle exec rspec spec/validators/

# 期待結果: 計150テスト成功（既存から移行）
```

---

## Phase 5: Orchestrator 実装

### Task 15-16: 新Compiler/Decompiler 実装

**依存**: Task 8-14
**所要時間**: 6-8時間
**並列**: 不可

#### 実装手順

##### Step 15: 新Compiler 実装

```bash
# 既存のcompiler.rbをバックアップ
cp lib/cornix/compiler.rb lib/cornix/compiler.rb.bak

# 全書き換え
vim lib/cornix/compiler.rb
```

**実装内容** (~150行):
```ruby
# frozen_string_literal: true

require_relative 'loaders/yaml_loader'
require_relative 'writers/vial_writer'
require_relative 'converters/keycode_converter'
require_relative 'converters/reference_converter'
require_relative 'position_map'

module Cornix
  class Compiler
    def initialize(config_dir)
      @config_dir = config_dir
      @keycode_converter = Converters::KeycodeConverter.new
      @reference_converter = Converters::ReferenceConverter.new(config_dir)
      @position_map = PositionMap.new("#{config_dir}/position_map.yaml")
    end

    def compile(output_path)
      # YAML → VialConfig
      vial_config = Loaders::YamlLoader.new(@config_dir).load(
        position_map: @position_map,
        keycode_converter: @keycode_converter,
        reference_converter: @reference_converter
      )

      # VialConfig → QMK Hash
      qmk_hash = vial_config.to_qmk(
        position_map: @position_map,
        keycode_converter: @keycode_converter,
        reference_converter: @reference_converter
      )

      # Hash → JSON
      Writers::VialWriter.new.write(qmk_hash, output_path)

      puts "✓ Compilation completed: #{output_path}"
    end
  end
end
```

##### Step 16: 新Decompiler 実装

```bash
# 既存のdecompiler.rbをバックアップ
cp lib/cornix/decompiler.rb lib/cornix/decompiler.rb.bak

# 全書き換え
vim lib/cornix/decompiler.rb
```

**実装内容** (~120行):
```ruby
# frozen_string_literal: true

require_relative 'loaders/vial_loader'
require_relative 'writers/yaml_writer'
require_relative 'converters/keycode_converter'
require_relative 'converters/reference_converter'
require_relative 'position_map'

module Cornix
  class Decompiler
    def initialize(vil_path)
      @vil_path = vil_path
      @keycode_converter = Converters::KeycodeConverter.new
      @position_map_template = PositionMap.new(
        File.join(__dir__, 'position_map.yaml')
      )
    end

    def decompile(output_dir)
      # JSON → VialConfig
      vial_config = Loaders::VialLoader.new(@vil_path).load(
        position_map: @position_map_template,
        keycode_converter: @keycode_converter
      )

      # VialConfig → YAML Hash
      yaml_hashes = vial_config.to_yaml_hashes(
        keycode_converter: @keycode_converter,
        reference_converter: Converters::ReferenceConverter.new(output_dir, prefer_name: true)
      )

      # Hash → YAML files
      Writers::YamlWriter.new(output_dir).write(yaml_hashes)

      puts "✓ Decompilation completed: #{output_dir}"
    end
  end
end
```

##### Step 15-16: 結合テスト作成

```bash
mkdir -p spec/integration
vim spec/integration/compile_spec.rb       # ~80行, 10テスト
vim spec/integration/decompile_spec.rb     # ~80行, 10テスト
```

**テスト内容**:
- ハッピーパスのフルフロー
- Fixture使用
- エラーハンドリング

##### テスト実行

```bash
bundle exec rspec spec/integration/

# 期待結果: 20テスト成功
```

---

## Phase 6: 検証 & クリーンアップ

### Task 17: Round-trip check

```bash
# 既存configをバックアップ
mv config config.backup

# 新実装でdecompile
ruby bin/decompile

# 新実装でcompile
ruby bin/compile

# 差分確認
ruby bin/diff_layouts

# 期待結果: === ✓ FILES ARE IDENTICAL ===
```

### Task 18: Spec整理

```bash
# 旧specを削除（新specに移行済み）
git rm spec/compiler_spec.rb
git rm spec/decompiler_spec.rb
git rm spec/keycode_resolver_spec.rb
git rm spec/reference_resolver_spec.rb
git rm spec/validator_spec.rb

# 全テスト実行
bundle exec rspec

# 期待結果: 約415テスト成功（重複削減後）
```

### Task 19: デッドコード削除

```bash
# 旧実装ファイルを削除（バックアップ済み）
git rm lib/cornix/compiler.rb.bak
git rm lib/cornix/decompiler.rb.bak

# 旧ファイルにdeprecationマーク追加（後方互換のため残す）
vim lib/cornix/keycode_resolver.rb
# コメント追加: # @deprecated Use Cornix::Converters::KeycodeConverter instead

vim lib/cornix/reference_resolver.rb
# コメント追加: # @deprecated Use Cornix::Converters::ReferenceConverter instead

vim lib/cornix/validator.rb
# コメント追加: # @deprecated Use Cornix::Validators::ModelValidator instead
```

### Task 20: ドキュメント更新

```bash
# 設計ドキュメントを .claude/ 以下に移動
mkdir -p .claude/refactor
mv .refactor/* .claude/refactor/

# CLAUDE.md 更新
vim .claude/CLAUDE.md
# リファクタリング結果を記録（新アーキテクチャ、設計判断、得られた知見）

# README.md 更新
vim README.md
# アーキテクチャセクション追加（モデル層の説明）

# README.en.md 更新
vim README.en.md
# 同様にアーキテクチャセクション追加

# MEMORY.md 更新
vim .claude/MEMORY.md
# 設計判断と重要なパターンを記録
```

---

## トラブルシューティング

### 問題1: Round-trip checkが失敗する

**症状**: `ruby bin/diff_layouts` で差分が出る

**デバッグ手順**:
1. どのセクションで差分が発生しているか確認
   ```bash
   ruby bin/diff_layouts | grep "DIFFER"
   ```

2. 該当セクションのロジックを確認
   - Layer差分 → `Layer#to_qmk`, `Layer#build_layout_array`
   - Macro差分 → `Macro#to_qmk`

3. 物理座標変換が正しいか確認
   ```ruby
   # spec/models/layer_spec.rb に詳細ログ追加
   puts "Physical: [#{phys_row}][#{phys_col}], Expected: #{expected}"
   ```

4. KeycodeConverter の変換が正しいか確認
   ```bash
   bundle exec rspec spec/converters/keycode_converter_spec.rb
   ```

### 問題2: テストが失敗する

**症状**: 特定のモデルテストが失敗

**デバッグ手順**:
1. エラーメッセージを確認
   ```bash
   bundle exec rspec spec/models/layer_spec.rb --format documentation
   ```

2. Fixture データを確認
   ```bash
   cat spec/fixtures/minimal_layout.json
   ```

3. デバッガーを使用
   ```ruby
   # spec内で binding.pry を追加（要 pry gem）
   require 'pry'
   binding.pry
   ```

### 問題3: 既存テストが壊れる

**症状**: 既存の493テストのうちいくつかが失敗

**対処**:
1. PositionMap拡張が原因の場合
   - 既存メソッドを変更していないか確認
   - 新規メソッドが既存コードに影響していないか確認

2. rollback して再実装
   ```bash
   git checkout lib/cornix/position_map.rb
   # 慎重に再実装
   ```

---

## 完了チェックリスト

### Phase 1
- [ ] PositionMap に5つのメソッド追加
- [ ] 15テスト追加
- [ ] 既存の493テスト全てパス
- [ ] Round-trip check 成功

### Phase 2
- [ ] Metadata & Settings モデル実装
- [ ] Macro & MacroCollection モデル実装
- [ ] TapDance & TapDanceCollection モデル実装
- [ ] Combo & ComboCollection モデル実装
- [ ] Layer & LayerCollection モデル実装
- [ ] VialConfig モデル実装
- [ ] 計~150テスト追加

### Phase 3
- [ ] VialLoader 実装
- [ ] YamlLoader 実装
- [ ] VialWriter 実装
- [ ] YamlWriter 実装
- [ ] 計~40テスト追加

### Phase 4
- [ ] KeycodeConverter 実装（既存から移行）
- [ ] ReferenceConverter 実装（既存から移行）
- [ ] ModelValidator 実装（既存から移行）
- [ ] 既存テストを新specに移行

### Phase 5
- [ ] 新Compiler 実装（~150行）
- [ ] 新Decompiler 実装（~120行）
- [ ] 結合テスト20テスト追加

### Phase 6
- [ ] Round-trip check 成功
- [ ] 旧spec削除
- [ ] 旧実装バックアップ
- [ ] deprecationマーク追加
- [ ] CLAUDE.md 更新
- [ ] README.md, README.en.md 更新
- [ ] MEMORY.md 更新
- [ ] 設計ドキュメントを .claude/refactor/ に移動

---

## 最終検証

```bash
# 全テスト実行
bundle exec rspec

# 期待結果: 約415テスト成功

# Round-trip check
mv config config.backup
ruby bin/decompile
ruby bin/compile
ruby bin/diff_layouts

# 期待結果: FILES ARE IDENTICAL

# パフォーマンス確認
time bundle exec rspec

# 期待結果: 2.0秒以内
```

---

## 参照

- [README.md](README.md): リファクタリング概要
- [architecture.md](architecture.md): アーキテクチャ設計
- [models.md](models.md): モデル設計詳細
- [data_flow.md](data_flow.md): データフロー図
- [coordinate_system.md](coordinate_system.md): 座標変換システム
