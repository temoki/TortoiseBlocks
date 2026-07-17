# TortoiseBlocks 開発プラン

[TortoiseGraphics2](https://github.com/temoki/TortoiseGraphics2) を描画エンジンとして使う、
子ども向けビジュアルプログラミング（ブロックエディタ）アプリ。
iOS / iPadOS / macOS を初期ターゲットとし、将来的に visionOS へ展開する。

> **進捗（2026-07-17 時点）**: M0〜M6 完了・M7（仕上げ）未着手。詳細は §13。

---

## 1. ゴール

- パレットからブロックをワークスペースへ並べ、実行するとカメがアニメーションで絵を描く
- くりかえし（ネスト可）・乱数を含むプログラムが組める
- ブロック列と等価な **Swift コードを表示**し、テキストプログラミングへの学習導線を作る
- 作品を **JSON（プロジェクト）/ SVG / PNG** で保存・共有できる
- 英語・日本語ローカライズ必須（将来多言語化しやすい構造にする）

## 2. 前提: TortoiseGraphics2 の活用ポイント

依存: `https://github.com/temoki/TortoiseGraphics2`（iOS/macOS/visionOS 26+, Swift 6.2）。
§12 の依頼 3 件が main にマージ済みのため、**次のベータタグを exact pin で採用**する
（タグ発行前に M0 を始める場合は一時的に `branch: "main"`）。

### 活用する API

| API | 用途 |
|---|---|
| `TortoiseCommand`（TortoiseCore） | ブロック展開の出力形式。Sendable + **Codable**（凍結ワイヤフォーマット、長期保存可） |
| `Tortoise`（@Observable） | 実行時のコマンド供給。追記・`reset()` は `TortoiseCanvas` が自動検知 |
| `Tortoise.reset()` | 再実行のたびのリセット（`.id()` での View 再生成は不要） |
| `TortoiseCanvas(_:player:)` + `TortoisePlayer` | 一時停止 / ステップ / シーク / ライブ速度変更（`speedOverride`）/ `currentCommandIndex` の観測 |
| `.tortoiseViewport(_:)` | 描画のビューポート制御（`.autoFit` / `.scaleToFit`） |
| `.speed(0...10)` コマンド | 作者側の再生速度（0 = 即時）。視聴者側の `speedOverride` が非 nil の間はそちらが優先 |
| `tortoise.svg(fit:)`（TortoiseSVG） | SVG 書き出しをそのまま利用 |
| `CommandPlayer.play(commands:)`（public） | 必要ならアプリ側で独自再生を組む余地あり |

### 設計に効く事実

1. **保存形式はアプリ側の Codable ブロックモデル**とし、実行時にコマンドへ変換する。
   `TortoiseCommand` も Codable になったが、これは「評価済みコマンド列」（§9）の保存に使うもので、
   プロジェクトファイルの本体はあくまでブロック木（ライブラリ型をドキュメントの主フォーマットにしない）
2. **`speed(0)` は即時描画**で、`CanvasModel.init` 内で全フレーム flush される
   → `ImageRenderer` による静的レンダリング（PNG 書き出し）が成立する
3. **pause 中の `step()` 再描画は Canvas クロージャ内の Observation 追跡に依存**
   （ライブラリ PR #28 レビューで指摘、実機未確認）→ M0 で最初に確認する（§15）

## 3. リポジトリ / モジュール構成

```
TortoiseBlocks/
├── PLAN.md
├── TortoiseBlocks.xcodeproj          # マルチプラットフォーム App ターゲット
├── App/                              # アプリ層（SwiftUI View, Document, 共有）
│   ├── TortoiseBlocksApp.swift
│   ├── Views/                        # Workspace / Palette / CanvasPane / CodePane ...
│   ├── Document/                     # FileDocument, UTType
│   └── Resources/                    # String Catalog, Assets
└── TortoiseBlocksKit/                # ローカル SwiftPM パッケージ（UI 非依存・swift test 可能）
    ├── Sources/TortoiseBlocksKit/
    │   ├── Model/                    # Block, BlockKind, NumberValue, BlockColor, Project
    │   ├── Engine/                   # BlockExpander（ブロック木 → コマンド列）
    │   └── CodeGen/                  # SwiftCodeGenerator（ブロック木 → Swift ソース）
    └── Tests/
```

- **TortoiseBlocksKit** は `TortoiseCore` のみに依存（SwiftUI 非依存）。モデル・展開・コード生成をすべてここに置き、ユニットテストを高速に回す
- アプリ層は Kit + `TortoiseUI` + `TortoiseSVG` に依存
- 状態管理は The SwiftUI Way に従い `@Observable` クラス + `@State` / `environment`。`ObservableObject` は使わない

## 4. ブロックモデル設計（TortoiseBlocksKit/Model）

### 型

```swift
/// ワークスペース上の 1 ブロック。安定 ID を持つ木構造・Codable。
struct Block: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var kind: BlockKind
}

enum BlockKind: Codable, Hashable, Sendable {
    // 移動系
    case forward(NumberValue)         // まえへ
    case backward(NumberValue)        // うしろへ
    case turnRight(NumberValue)       // みぎへまわる（度）
    case turnLeft(NumberValue)        // ひだりへまわる（度）
    case home                         // ホームへもどる
    // ペン系
    case penUp
    case penDown
    case penColor(BlockColor)
    case penWidth(NumberValue)
    // 塗り系
    case fillColor(BlockColor)
    case beginFill                    // 塗りはじめ
    case endFill                      // 塗りおわり
    // 制御系（子ブロック列を持つ）
    case repeatBlock(count: NumberValue, body: [Block])
}

/// 数値引数。「乱数」は独立ブロックではなく引数の値として表現する
/// （どの数値スロットにも差し込める＝Scratch 同様の柔軟さ）。
enum NumberValue: Codable, Hashable, Sendable {
    case literal(Double)
    case random(min: Double, max: Double)   // 実行のたびに評価
}

/// 保存用のカラーパレット。実行時に TortoiseCore.Color へ変換。
enum BlockColor: String, Codable, CaseIterable, Sendable {
    case black, white, red, green, blue, yellow, orange, purple, cyan, magenta
}
```

### 保存スキーマ（プロジェクトファイル）

```swift
struct BlocksProject: Codable, Sendable {
    var schemaVersion: Int            // = 1。将来のマイグレーション用
    var title: String
    var blocks: [Block]               // トップレベルのブロック列
}
```

- JSON エンコードして独自 UTType `space.hiraku.tortoiseblocks`（拡張子 `.tortoiseblocks`）で保存
- `BlockKind` の Codable は将来ブロック追加しても既存ファイルが壊れないよう、
  未知ケースをデコード時に安全に落とす（もしくはエラー表示する）方針をテストで担保する

### 設計判断

- **enum + 子配列**の木構造：ブロック＝値型・Codable という要件に最も素直。編集操作（挿入/削除/移動）は
  `id` パスで木を辿る純関数として Kit 内に実装し、テスト可能にする
- **ID は UUID**：SwiftUI の `ForEach` / drag & drop / 実行ハイライトの全てで安定識別子として使う
- 「もし」ブロックは初期セット外だが、`BlockKind` に case を足すだけで済む構造にしておく

## 5. 実行エンジン（TortoiseBlocksKit/Engine）

### 展開: ブロック木 → コマンド列

```swift
struct ExpandedCommand: Sendable {
    let command: TortoiseCommand
    let blockID: UUID                 // 実行中ブロックのハイライトに使う
}

enum BlockExpander {
    /// 乱数を評価しつつ木を平坦化。RNG を注入してテストを決定的にする。
    static func expand(
        _ blocks: [Block],
        using rng: inout some RandomNumberGenerator,
        limit: Int = 10_000
    ) throws -> [ExpandedCommand]
}
```

- `repeatBlock` は count 回ぶん body を展開（乱数 count は展開時に 1 回評価、body 内の乱数は毎周評価）
- **展開上限（例: 10,000 コマンド）**でネストした repeat の爆発をガードし、超過時は子ども向けの分かりやすいエラーにする

### 実行モード（アプリ層 `RunnerModel` @Observable、`TortoisePlayer` ベース）

| 操作 | 実現方法 |
|---|---|
| 実行 | `tortoise.reset()` → 展開済みコマンドを一括投入。`TortoiseCanvas(_:player:)` がアニメーション再生 |
| 一時停止 / 再開 | `player.isPaused`（pause 中はキャンバスの再描画も完全停止） |
| ステップ | `player.step()`（pause 中に 1 コマンドずつ。即時コミット） |
| シーク | `player.seek(to:)`（前方・後方どちらも可 → スクラバー UI も実装可能） |
| 速度スライダー | `player.speedOverride`（1〜10 + 「一気に描く」= 0）。**再生中のライブ変更可・巻き戻りなし** |
| 停止 / リセット | `tortoise.reset()`（`.id()` での View 再生成は不要） |

- **ブロックハイライト**: `player.currentCommandIndex`（@Observable）→ `ExpandedCommand` 配列の
  同 index → `blockID` を `RunnerModel.currentBlockID` に反映し、ワークスペース側が該当ブロックを
  強調表示する（教育上の主要フィーチャー）。**通常実行のアニメーション中も常時ハイライトできる**
- ストリーム内 `.speed()` は使わず、速度は視聴者制御（`speedOverride`）に一本化する
  （ブロックに「はやさ」ブロックを将来追加する場合のみ作者側 `.speed()` を使う）

## 6. コード生成（TortoiseBlocksKit/CodeGen）

ブロック木から Tortoise API の Swift ソースを生成して表示する（学習導線）。

```swift
// 生成例
let 🐢 = Tortoise()
🐢.penColor = .orange
for _ in 1...8 {
    🐢.forward(Double.random(in: 50...150))
    🐢.right(45)
}
```

- `repeatBlock` → `for _ in 1...n { }`、`NumberValue.random` → `Double.random(in:)`
- インデント整形のみ（シンタックスハイライトは `AttributedString` で軽量に。外部依存なし）
- 表示はワークスペース横のインスペクタ / シート。コピー用の `ShareLink` / コピーボタン付き

## 7. UI 設計（アプリ層）

### 画面構成

```
┌─────────┬───────────────────┬───────────────┐
│ パレット │   ワークスペース      │  キャンバス      │
│ (縦一覧) │  (ブロック列＋ネスト)  │ TortoiseCanvas │
│         │                   │  ▶ ⏭ ⏹ 🐢速度━━ │
└─────────┴───────────────────┴───────────────┘
```

- **iPad / Mac**: 3 ペイン（パレット | ワークスペース | キャンバス）。コード表示はキャンバス側のタブまたはインスペクタ
- **iPhone**: ワークスペースとキャンバスを上下分割 or タブ切替。パレットは下部シート
- レイアウト切替は `ViewThatFits` / size class で行い、`AnyLayout` で子 View の identity を保つ

### ドラッグ & ドロップ

- `Block` を `Transferable`（`CodableRepresentation` + 独自 UTType）にし、
  SwiftUI `draggable` / `dropDestination` で パレット→ワークスペース / ワークスペース内の並べ替え / repeat への入れ子 を実現
- ドロップ位置のインジケータ（挿入線）は各ブロック行の上下エッジ判定で描く
- **タップで追加（パレットをタップ→末尾に追加）を併設**：低学年・アクセシビリティ・iPhone での操作性のためのフォールバック。MVP はこちらを先に完成させ、D&D を重ねる
- 削除はスワイプ / 選択して削除ボタン / パレット側へドラッグ
- **Undo/Redo**: 編集操作を純関数（旧木 → 新木）にしているので、`UndoManager` 連携は木のスナップショット差し替えで実装

### ブロックの見た目

- カテゴリ別カラー（移動=青、ペン=紫、塗り=緑、制御=オレンジ 等）。色はアセットカタログでライト/ダーク両対応
- 数値スロットはタップでステッパー/テンキー popover、乱数はサイコロアイコンでトグル
- カラースロットはパレット popover
- フォント/余白は `@ScaledMetric` + セマンティックフォントで Dynamic Type 対応

## 8. 永続化・ドキュメント

- **`DocumentGroup` + `FileDocument`** を採用（JSON = `BlocksProject`）
  - iOS/iPadOS/macOS のドキュメントブラウザ・iCloud Drive・ファイル共有が標準で手に入る
  - 教育現場での「ファイルを渡す」運用（AirDrop・クラスルーム）と相性が良い
- 新規ドキュメントにはサンプル（正方形・星など）をテンプレートとして用意

## 9. 共有・書き出し

| 形式 | 実装 |
|---|---|
| SVG | 実行済みコマンド列から `Tortoise` を再構築し `svg(fit:)` → `fileExporter` / `ShareLink` |
| PNG | `speed(0)` の `Tortoise` + `TortoiseCanvas` を `ImageRenderer` でラスタライズ（§2「設計に効く事実 2」により静的レンダリング可能）。書き出し解像度は 1x/2x/3x 選択 |
| プロジェクト | `.tortoiseblocks` ファイルそのもの（ドキュメントとして共有） |

- 「最後に実行した結果」を書き出す仕様にする（乱数を含む作品で、見えている絵と書き出しが一致するよう、実行時に評価済みコマンド列を保持しておく）
- 評価済みコマンド列は `TortoiseCommand` の Codable（凍結ワイヤフォーマット・長期保存可）で
  そのままドキュメント内に永続化できる → アプリ再起動後も「見えている絵＝書き出される絵」を保証

## 10. ローカライズ

- **String Catalog**（`Localizable.xcstrings`）で en / ja。開発言語は en
- ブロック名・カテゴリ名・エラーメッセージ・アクセシビリティラベルをすべてキー化
- 子ども向け日本語はひらがな主体（「まえへ すすむ」「◯かい くりかえす」）。トーンガイドを README に残す
- 生成 Swift コードは言語非依存（API 名のまま）
- 将来の多言語化: ブロック名がキー化されていれば言語追加は xcstrings への追記のみ

## 11. アクセシビリティ

- ブロックはネイティブコントロール（`Button` 等）ベースで構成し、`accessibilityRepresentation` / ラベルを必ず付与
- D&D 不要の代替操作（タップ追加・選択して移動ボタン）を常に用意
- VoiceOver でブロック列を読み上げ可能に（「まえへ 100 すすむ、2 ばんめ」）
- 色だけに頼らない（カテゴリはアイコン + 色）

## 12. TortoiseGraphics2 側への機能要望（対応済み）

依頼した 3 件はすべてライブラリ本体にマージ済み（2026-07-17）:

1. **再生制御の公開 API** — `TortoisePlayer`（pause / step / seek / speedOverride、
   `currentCommandIndex` の観測）: [#23](https://github.com/temoki/TortoiseGraphics2/issues/23)
2. **`Tortoise.reset()` + 変更検知の堅牢化**（`TortoiseChangeKey` によるインスタンス差し替え検知込み）:
   [#24](https://github.com/temoki/TortoiseGraphics2/issues/24)
3. **`TortoiseCommand` / `Color` / `Point` / `Size` の Codable 準拠**
   （CodingKeys 明示・長期保存フォーマットとして安定保証）: [#25](https://github.com/temoki/TortoiseGraphics2/issues/25)

これにより当初の制約（再生制御 API 非公開・append-only・Codable 非対応）に対する
workaround（`.id()` 再生成・速度変更 = 再実行・ハイライトはステップ実行のみ）は不要になり、
§2 / §5 / §9 / §15 は `TortoisePlayer` / `reset()` / Codable を前提とした内容に更新済み。

## 13. マイルストーン

| M | 内容 | 完了条件 | 状態 |
|---|---|---|---|
| **M0** | プロジェクト雛形：xcodeproj + Kit パッケージ + TortoiseGraphics2 依存。ハードコードしたコマンド列が `TortoiseCanvas(_:player:)` で動く walking skeleton | iOS/macOS 両方でビルド・実行でき、pause 中 `step()` の再描画を実機確認済み（§15） | ✅ 2026-07-17（`e8e7b76`） |
| **M1** | Kit 完成：ブロックモデル / BlockExpander / CodeGen + ユニットテスト（乱数注入・展開上限・Codable 往復・コード生成スナップショット） | `swift test` グリーン | ✅ 2026-07-17（`b3f3e96`） |
| **M2** | エディタ MVP：パレット（タップ追加）＋ワークスペース表示・並べ替え・削除・引数編集・repeat ネスト・Undo | ブロックで正方形プログラムが組める | ✅ 2026-07-17（`653ab1e`） |
| **M3** | 実行体験：実行 / 一時停止 / ステップ / シーク / 速度スライダー（ライブ変更）＋実行中ブロックの常時ハイライト（`TortoisePlayer` ベース） | くりかえし＋乱数の作品が動く | ✅ 2026-07-17（`9bd22a8`） |
| **M4** | D&D 本実装（draggable/dropDestination、挿入インジケータ、ネストへのドロップ） | パレット→ワークスペース→ネストまで D&D で完結 | ✅ 2026-07-17（`9cb5270`） |
| **M5** | ドキュメント化：DocumentGroup 保存/読込、テンプレート、ローカライズ（en/ja） | ファイル往復・言語切替が動く | ✅ 2026-07-17（`9b5183e`） |
| **M6** | 共有：SVG / PNG 書き出し、コード表示ペイン仕上げ | 作品を書き出して他アプリへ渡せる | ✅ 2026-07-17（`153a6b1` + 修正 `6815d2f`） |
| **M7** | 仕上げ：アクセシビリティ監査、iPhone レイアウト最適化、macOS メニュー/ショートカット、App Store 準備 | TestFlight 配布 | ⬜ 未着手 |
| 将来 | visionOS 対応、「もし」ブロック・変数・関数ブロック、作品ギャラリー、多言語追加 | — | — |

M1（UI 非依存の Kit）を最初に固めることで、以降の UI 反復中もロジックの正しさをテストで担保し続ける。

### 実装で計画から変えた点・未消化の項目

- **M2**: 挿入先の指定は「ブロック選択」でなく **repeat ヘッダの「ここへついか」トグル**方式に。
  D&D 導入後もアクセシビリティ代替操作（§11)としてそのまま併存している
- **M3**: シークスクラバーは M3 で前倒し実装（ライブラリの `seek(to:)` が素直に繋がったため）
- **M4**: 挿入インジケータは計画の「行の上下エッジ判定」でなく、**行間ギャップ（DropGap）方式**に簡素化。
  y 座標計算なしで (containerID, index) の挿入セマンティクスが正確に決まる
- **M5**: 新規ドキュメントは空で開始。**サンプルテンプレートは未実装**（→ M7 or 将来で再検討）
- **M6**: 書き出しは `fileExporter` のみ（**`ShareLink` は未実装**）。**PNG は @2x 固定**
  （計画の 1x/2x/3x 解像度選択は未実装）
- **§7 のうち未実装**: 削除のスワイプ操作・パレット側へのドラッグ削除（現状は行の削除ボタンのみ）
- 既知の実装上の教訓: 同一ビューへ同種のプレゼンテーション modifier（`fileExporter` 等）を
  複数付けると後勝ちで先のものが機能しない（`6815d2f` で 1 つに統合済み）

## 14. テスト戦略

- **Kit（swift-testing）**: 展開の網羅テスト（各 BlockKind → 期待コマンド列）、乱数の決定的テスト（seed 注入）、
  展開上限、Codable 往復 + 旧スキーマ互換、CodeGen はスナップショットテスト
- **アプリ層**: 編集操作（挿入/移動/削除/Undo）は純関数なので Kit 側でテスト。
  描画結果の確認は TortoiseGraphics2 側のテスト資産（snapshot testing）と同じ方式を必要に応じて導入
- CI: GitHub Actions（macOS runner）で `swift test`（Kit）+ `xcodebuild build`（App、iOS/macOS）

## 15. リスクと対応

| リスク | 対応 |
|---|---|
| ネストした木構造への SwiftUI D&D が複雑化 | M2 でタップ追加＋並べ替えを先に完成させ、D&D は M4 に分離。挿入判定はフラットな行リスト（depth 付き）に投影して単純化する |
| pause 中の `step()` 再描画が Canvas クロージャ内の Observation 追跡に依存（ライブラリ PR #28 レビューで指摘、実機未確認） | M0 の walking skeleton で最初に確認する。NG の場合は「body 内で `currentCommandIndex` を読んで依存を張る」1 行修正を upstream に出す |
| repeat ネストによるコマンド爆発 | 展開上限 + 子ども向けエラーメッセージ（M1 でテスト） |
| beta 依存の API 変動 | 自作ライブラリなので変更は自分起点。Package.swift では exact pin し、更新は意図的に行う |
| OS 26+ 要件による対象デバイス制限 | ライブラリ要件由来で回避不可。教育導入時の対象 OS として明記 |
