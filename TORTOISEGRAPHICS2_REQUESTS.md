# TortoiseGraphics2 への修正依頼事項

TortoiseBlocks（ブロックエディタアプリ）開発で判明したライブラリ側の制約のうち、
upstream（[temoki/TortoiseGraphics2](https://github.com/temoki/TortoiseGraphics2)）で
対応するもののまとめ。背景は [PLAN.md](PLAN.md) §2 / §12 を参照。

現行バージョンは `2.0.0-beta7`（正式リリース前）のため、**破壊的変更を伴う API 追加も許容**する前提。

---

## 依頼 1: 再生制御 API の公開（優先度: 高）

> 登録済み issue: <https://github.com/temoki/TortoiseGraphics2/issues/23>

### 現状

- 再生ロジックは `TortoiseUI` の `CanvasModel`（internal）に閉じており、
  `TortoiseCanvas` が `TimelineView` で自動再生するのみ
- 外部からは 一時停止 / 再開 / ステップ / シーク / 再生中の速度変更 ができず、
  「現在どのコマンドを描画中か」も観測できない

### TortoiseBlocks 側の困りごと

| 欲しい機能 | 現状の workaround | 問題 |
|---|---|---|
| 実行中ブロックのハイライト | ステップ実行モード（speed 0 で 1 コマンドずつ追記）のみ対応 | 通常実行（アニメーション再生）中はハイライト不可 |
| 速度スライダーのライブ反映 | スライダー変更時に最初から再実行 | 描画が巻き戻る。長いプログラムで体験が悪い |
| 一時停止 → そこからステップ | 不可能 | 教育用途では「途中で止めて 1 手ずつ確認」が核になる操作 |

### 提案 API

```swift
// TortoiseUI に新設
@Observable @MainActor
public final class TortoisePlayer {
    public init()

    // 観測（読み取り専用）
    /// 直近にコミットされたコマンドの index（-1 = 未開始）。
    /// CommandPlayer はコマンドと PlaybackFrame を 1:1 で生成するため、
    /// 内部的には CanvasModel.currentFrameIndex の公開に相当する。
    public private(set) var currentCommandIndex: Int
    public private(set) var isFinished: Bool

    // 制御
    public var isPaused: Bool
    /// 一時停止中に 1 コマンドぶん進める
    public func step()
    /// 指定コマンド位置まで再構築してジャンプ（前方・後方とも可）
    public func seek(to commandIndex: Int)
    /// nil = ストリーム内の .speed() に従う。非 nil ならそれを優先（ライブ変更可）
    public var speedOverride: Double?
}

// TortoiseCanvas に opt-in の受け口を追加（既存 API は無変更）
public init(_ tortoise: Tortoise, player: TortoisePlayer)
```

### 実装メモ

- `CanvasModel` をそのまま public にするのではなく、公開面を絞った `TortoisePlayer` を
  かぶせる形を推奨（`frames` や `elements` など内部表現は隠したまま将来変更できる）
- `Tortoise.speed` / ストリーム内 `.speed()` は **現状のまま維持する**。二層構造として整理する:
  - ストリーム内 `.speed()` = **作者のテンポ指定**（作品の一部。Preview の instant-mode や
    closure 形式 API が依存）
  - `speedOverride` = **視聴者側の再生制御**（動画プレイヤーの倍速ボタンに相当。作品は書き換えない）
  - 優先規則「`speedOverride` が非 nil の間はストリーム内 `.speed()` より優先される」を
    DocC に明文化する
- `seek` の後方ジャンプは、`frames` が init 時に全計算済みなので
  「先頭から `advance()` を再適用」する素朴な実装で十分（要素数は展開上限内に収まる想定）
- `isPaused == true` の間は `TimelineView` のスケジュールを止め、再描画を発生させない
  （既存の `paused: model.isFinished` と同じ機構に乗せる）

### 受け入れ条件

- [ ] `TortoiseCanvas(_:player:)` で pause / resume / step / seek / speedOverride が機能する
- [ ] `currentCommandIndex` が @Observable として SwiftUI から追従できる
- [ ] `player` を渡さない既存利用コード（`TortoiseCanvas(🐢)` / closure 形式）の挙動が変わらない
- [ ] speedOverride 変更時に描画位置が巻き戻らない（進行位置を維持したまま速度だけ変わる）
- [ ] `speedOverride` とストリーム内 `.speed()` の優先規則が DocC に明記されている

---

## 依頼 2: `Tortoise.reset()` と変更監視の堅牢化（優先度: 中）

> 登録済み issue: <https://github.com/temoki/TortoiseGraphics2/issues/24>

### 現状

- `Tortoise.commands` は append-only。`clear()` は「clear コマンドの追記」であり、
  コマンド列自体は増え続ける
- `TortoiseCanvas` は `task(id: tortoise.commands.count)` で追記を検知している

### TortoiseBlocks 側の困りごと

- プログラムの再実行のたびに `Tortoise` を作り直し、`TortoiseCanvas` を `.id()` で
  再生成する workaround が必要
- 再実行を繰り返すアプリではコマンド列（とリプレイコスト）が際限なく増えるため、
  `clear()` では代替にならない

### 提案 API

```swift
extension Tortoise {
    /// コマンド列を破棄し、状態（位置・向き・ペン・塗り・背景）を初期値へ戻す。
    /// canvasSize は維持する。Python turtle の reset() 相当。
    public func reset()
}
```

### あわせて必要な修正: 変更監視キーの是正

`task(id: commands.count)` は **個数** を id にしているため、`reset()` 導入後は
以下のケースで検知漏れが起きる:

```swift
// 同一 MainActor ターン内で reset → 同じ長さのプログラムを再投入すると
// count が 4 → 4 のまま（SwiftUI は最終値しか観測しない）→ task(id:) が発火しない
🐢.reset()
for command in newProgram { apply(command) }  // 旧: 4 個 / 新: 4 個
```

対応案: `Tortoise` に単調増加の内部カウンタを持たせ、それを監視キーにする。
TortoiseCore と TortoiseUI は同一パッケージ内なので **`package` アクセスレベル**で足り、
公開 API を増やさずに済む。

```swift
// Tortoise 内部
package private(set) var mutationCount: Int  // record() / reset() のたびに +1

// TortoiseCanvas 側
.task(id: tortoise.mutationCount) { ... }
```

### 受け入れ条件

- [ ] `reset()` 後に `commands.isEmpty`、状態が `TortoiseState.default` に戻る（canvasSize は維持）
- [ ] `reset()` → 直後に同数のコマンドを再投入しても `TortoiseCanvas` が新しい絵を描き直す
- [ ] `isFilling` 中の `reset()` でフィルが正しく破棄される（`clear()` と同じセマンティクス）

---

## 依頼 3: 主要な値型への Codable 準拠（優先度: 低）

> 登録済み issue: <https://github.com/temoki/TortoiseGraphics2/issues/25>

### 現状

`TortoiseCommand` / `Color` / `Point` / `Size` は `Sendable`・`Equatable`（一部 `Hashable`）だが
`Codable` ではない。

### TortoiseBlocks 側のユースケース

- 「最後に実行した評価済みコマンド列」を保存し、アプリ再起動後も
  画面表示と SVG/PNG 書き出しの一致を保証したい（乱数を含む作品で必須）
- テストフィクスチャ / ゴールデンファイルとしてコマンド列を JSON で持ちたい

※ ブロックの保存形式はアプリ独自モデルで持つ方針のため必須ではないが、
上記 2 点でそのまま効く。

### 提案

対象: `TortoiseCommand`, `Color`, `Point`, `Size`

**合成 Codable ではなく、明示的な `CodingKeys` / カスタム実装でエンコード形式を固定し、
長期保存フォーマットとして安定性を保証する**（決定済み方針）。

```swift
// 例: ワイヤフォーマットのキーを Swift のケース名から独立させる
extension TortoiseCommand: Codable {
    private enum CodingKeys: String, CodingKey {
        case forward, rotate, home, setPosition, setHeading, ...
    }
    // encode/decode を明示実装（将来ケースをリネームしても保存データは不変）
}
```

### 実装メモ

- 合成 Codable はケース名がそのままキーになり、リネームが保存データを壊すため採用しない。
  キーを明示することで Swift の識別子とワイヤフォーマットを分離する
- 語彙（forward / rotate / pen / fill …）はタートルグラフィックスというドメイン自体が
  安定しているため、フォーマット固定の実質コストは低い
- 安定性保証の範囲（キー・構造は 2.x 系で不変、ケース追加は後方互換）を DocC に明記する
- TortoiseCore は Foundation-only のため依存追加なし

### 受け入れ条件

- [ ] 全ケースの round-trip（encode → decode → Equatable 一致）テスト
- [ ] **エンコード済み JSON のスナップショットテスト**（形式が意図せず変わったら検知できる）
- [ ] 安定性保証（長期保存可・2.x 系でフォーマット不変）を DocC に明記

---

## 対応順の提案

| 順 | 依頼 | issue | 理由 |
|---|---|---|---|
| 1 | 依頼 2（reset + mutationCount） | [#24](https://github.com/temoki/TortoiseGraphics2/issues/24) | 小さく独立しており、TortoiseBlocks M3（実行体験）の workaround を即解消できる |
| 2 | 依頼 1（TortoisePlayer） | [#23](https://github.com/temoki/TortoiseGraphics2/issues/23) | 最も効果が大きい。TortoiseBlocks M3〜M7 の体験品質（ライブ速度変更・実行中ハイライト・一時停止）を決める |
| 3 | 依頼 3（Codable） | [#25](https://github.com/temoki/TortoiseGraphics2/issues/25) | いつでも入れられる。方針は決定済み（CodingKeys 明示＋長期保存フォーマットとして安定保証） |

いずれも `2.0.0` 正式リリース前に入れられれば、TortoiseBlocks 側は beta の exact pin を
順次上げるだけで追従できる。
