# TortoiseBlocks 開発プラン

[TortoiseGraphics2](https://github.com/temoki/TortoiseGraphics2) を描画エンジンとして使う、
子ども向けビジュアルプログラミング（ブロックエディタ）アプリ。
iOS / iPadOS / macOS を初期ターゲットとし、将来的に visionOS へ展開する。

---

## 1. ゴール

- パレットからブロックをワークスペースへ並べ、実行するとカメがアニメーションで絵を描く
- くりかえし（ネスト可）・乱数を含むプログラムが組める
- ブロック列と等価な **Swift コードを表示**し、テキストプログラミングへの学習導線を作る
- 作品を **JSON（プロジェクト）/ SVG / PNG** で保存・共有できる
- 英語・日本語ローカライズ必須（将来多言語化しやすい構造にする）

## 2. 前提: TortoiseGraphics2 の活用ポイントと制約

依存: `https://github.com/temoki/TortoiseGraphics2`（現行 `2.0.0-beta7`、iOS/macOS/visionOS 26+, Swift 6.2）

### 活用する API

| API | 用途 |
|---|---|
| `TortoiseCommand`（TortoiseCore） | ブロック展開の出力形式。Sendable な値型 |
| `Tortoise`（@Observable, append-only） | 実行時のコマンド供給。追記は `TortoiseCanvas` が自動検知 |
| `TortoiseCanvas` + `.tortoiseViewport(_:)` | 描画・アニメーション再生（`.autoFit` / `.scaleToFit`） |
| `.speed(0...10)` コマンド | 再生速度（0 = 即時） |
| `tortoise.svg(fit:)`（TortoiseSVG） | SVG 書き出しをそのまま利用 |
| `CommandPlayer.play(commands:)`（public） | 必要ならアプリ側で独自再生を組む余地あり |

### 制約（設計に効くもの）

1. **`TortoiseCommand` は Codable ではない** → 保存形式はアプリ側の Codable ブロックモデルとし、実行時にコマンドへ変換する（ライブラリの型をシリアライズ境界に持ち込まない。将来のライブラリ変更にも強い）
2. **再生制御 API が非公開**（`CanvasModel` は internal）→ 一時停止・シーク・再生中のライブ速度変更・「現在どのコマンドを描画中か」の取得はできない
   - ステップ実行は「アプリ側から Tortoise に 1 コマンドずつ追記」で実現する（追記検知で即反映される）
   - 通常実行は速度をプレフィックスコマンドで与え、スライダー変更時は再実行（restart）で対応
   - 恒久対応は §12 のライブラリ改善で解消する
3. **`Tortoise` は append-only（リセット不可）** → 再実行のたびに新しい `Tortoise` を生成し、`TortoiseCanvas` を `.id()` で作り直す
4. **`speed(0)` は即時描画**で、`CanvasModel.init` 内で全フレーム flush される → `ImageRenderer` による静的レンダリング（PNG 書き出し）が成立する

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

### 実行モード（アプリ層 `RunnerModel` @Observable）

| モード | 実現方法 | 備考 |
|---|---|---|
| 実行 | 新規 `Tortoise` に `.speed(スライダー値)` + 全コマンドを一括追記し、ライブラリのアニメーション再生に任せる | なめらかな線分アニメーションが得られる。再生中の速度変更は「再実行」で反映（§2 制約 2） |
| ステップ | 新規 `Tortoise`（speed 0）に、ボタンタップごとに 1 コマンド追記 | 即時描画で 1 手ずつ進む。`blockID` で該当ブロックをハイライト |
| 停止/リセット | `Tortoise` を破棄し `TortoiseCanvas` を `.id()` で再生成 | append-only 制約への対応 |

- 速度スライダー（1〜10 + 「一気に描く」= 0）は実行開始時に `.speed()` として先頭に挿入
- ステップ実行では `ExpandedCommand.blockID` を `RunnerModel.currentBlockID` に反映し、
  ワークスペース側が該当ブロックを強調表示する（教育上の主要フィーチャー）

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
| PNG | `speed(0)` の `Tortoise` + `TortoiseCanvas` を `ImageRenderer` でラスタライズ（§2 制約 4 により静的レンダリング可能）。書き出し解像度は 1x/2x/3x 選択 |
| プロジェクト | `.tortoiseblocks` ファイルそのもの（ドキュメントとして共有） |

- 「最後に実行した結果」を書き出す仕様にする（乱数を含む作品で、見えている絵と書き出しが一致するよう、実行時に評価済みコマンド列を保持しておく）

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

これにより §2 の制約 1〜3 と、それに対応する §5 の workaround（`.id()` 再生成・
速度変更 = 再実行・ハイライトはステップ実行のみ）は不要になった。
次のベータリリースを exact pin で取り込み、§5 の実行モード設計は `TortoisePlayer` ベースに簡素化する。

## 13. マイルストーン

| M | 内容 | 完了条件 |
|---|---|---|
| **M0** | プロジェクト雛形：xcodeproj + Kit パッケージ + TortoiseGraphics2 依存。ハードコードしたコマンド列が `TortoiseCanvas` で動く walking skeleton | iOS/macOS 両方でビルド・実行できる |
| **M1** | Kit 完成：ブロックモデル / BlockExpander / CodeGen + ユニットテスト（乱数注入・展開上限・Codable 往復・コード生成スナップショット） | `swift test` グリーン |
| **M2** | エディタ MVP：パレット（タップ追加）＋ワークスペース表示・並べ替え・削除・引数編集・repeat ネスト・Undo | ブロックで正方形プログラムが組める |
| **M3** | 実行体験：実行 / 停止 / ステップ実行（ブロックハイライト）/ 速度スライダー | くりかえし＋乱数の作品が動く |
| **M4** | D&D 本実装（draggable/dropDestination、挿入インジケータ、ネストへのドロップ） | パレット→ワークスペース→ネストまで D&D で完結 |
| **M5** | ドキュメント化：DocumentGroup 保存/読込、テンプレート、ローカライズ（en/ja） | ファイル往復・言語切替が動く |
| **M6** | 共有：SVG / PNG 書き出し、コード表示ペイン仕上げ | 作品を書き出して他アプリへ渡せる |
| **M7** | 仕上げ：アクセシビリティ監査、iPhone レイアウト最適化、macOS メニュー/ショートカット、App Store 準備 | TestFlight 配布 |
| 将来 | visionOS 対応、「もし」ブロック・変数・関数ブロック、作品ギャラリー、多言語追加 | — |

M1（UI 非依存の Kit）を最初に固めることで、以降の UI 反復中もロジックの正しさをテストで担保し続ける。

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
| 再生中の速度変更・実行モードのハイライトができない（ライブラリ制約） | MVP は「速度変更 = 再実行」「ハイライトはステップ実行のみ」。§12-1 の upstream 対応で解消 |
| repeat ネストによるコマンド爆発 | 展開上限 + 子ども向けエラーメッセージ（M1 でテスト） |
| beta 依存（2.0.0-beta7）の API 変動 | 自作ライブラリなので変更は自分起点。Package.swift では exact pin し、更新は意図的に行う |
| OS 26+ 要件による対象デバイス制限 | ライブラリ要件由来で回避不可。教育導入時の対象 OS として明記 |
