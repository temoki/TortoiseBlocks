# Product Hunt 投稿内容

Tortoise Blocks を Product Hunt に出すときの入稿内容と、その判断の理由。
`docs/` は GitHub Pages に公開されないので、ここは作業用のメモ置き場。

調査日 2026-09-12 / 対象バージョン v1.1.0。

## 訴求軸

**ブロック → Swift**。「同じプログラムを2つの記法で同時に見せている」を主役にする。

Product Hunt の読者はメイカー・インディー開発者・デザイナーで、「子ども向け
教育アプリ」だけでは埋もれる。このプロダクトが本当に届けたいのは
**開発者である親**なので、その交差点を狙う。Papert の物語は tagline ではなく
First comment に置く（ここが一番読まれる）。

採らなかった軸と理由:

- **再帰（9個のブロックが木になる）** — 話題性は一番高いが、対象が子どもで
  あることが伝わりにくい。Description の一文として残す
- **子どもに何も求めない（通信コード0行 / MIT）** — PH で共感は集めやすいが、
  機能の魅力が後回しになる。First comment の末尾に置く
- **Vision Pro** — 目新しさはあるが、あくまでビューアなので主役にしにくい

---

## 入稿フィールド

### Name

```
Tortoise Blocks
```

### Tagline（60字以内 / 46字）

```
Block coding for kids that grows up into Swift
```

対案: `Block coding for kids, with the real Swift beside it` (52字)。
事実としては正確だが感情が動かない。採用案は why.html の結論
（「子どもがこれを卒業する日のために作られている」）そのもの。

### Description（260字以内 / 256字）

```
Snap blocks into a program, press play, and a tortoise draws your picture line by line — while the pane beside it shows the same program as real, syntax-colored Swift. Blocks you name can call themselves, so nine of them draw a tree. iPad, Mac, Vision Pro.
```

「無料・オープンソース・通信なし」はここに入れず First comment に回した。
260字では再帰の一言（`nine of them draw a tree`）のほうが投資効率が高い。

### Launch tags（3つまで）

| タグ | breadcrumb / 規模 | 狙い |
|---|---|---|
| `Kids` | `Home > Launch tags > Kids & Parenting > Kids` / 620 products | 子ども向けの正式な置き場。母数が小さく、このタグのリーダーボードで上位を取る現実味が一番高い |
| `Education` | `Home > Launch tags > Education` / 5,246 products | 最大の browse 流入面。順位は狙えないが母数が違う |
| `Open Source` | Launch tag として実在（"Sharing is caring."） | 開発者層への到達。「通信コードが1行もない」を確かめられる、という主張の裏付け |

注意点:

- 上の3つは **投稿フォームの補完にすべて存在することを確認済み**
- **`Apps for Kids` は launch tag ではない。** browse 用の categories 側の名前で、
  投稿フォームの補完には出てこない。正しいのは `Kids`
- `Kids` は語が短く補完に親グループ `Kids & Parenting` や `Parenting`（387件、
  育児支援ツール寄り）が混ざる。breadcrumb が `Kids & Parenting > Kids` の
  ものを選ぶ
- `iPad`（3,195件）・`Mac`（3,512件）も launch tag として実在する。Apple
  ユーザー層を狙うなら `Education` と差し替えが対案。ただしプラットフォームは
  App Store バッジとギャラリーで伝わるので、3枠のうち1つを使うのは割に合わない
- `Online learning`（`Education` の兄弟タグ）は講座・コース系が主で、アプリ
  単体は場違いに見えるおそれ

### Links

| 項目 | URL |
|---|---|
| Website | `https://temoki.github.io/TortoiseBlocks/?lang=en` |
| App Store | `https://apps.apple.com/app/id6798677334` |
| GitHub（アプリ） | `https://github.com/temoki/TortoiseBlocks` |
| GitHub（エンジン） | `https://github.com/temoki/TortoiseGraphics2` |

`?lang=en` を付けないと閲覧者の環境次第で日本語表示になる。

エンジン側 [TortoiseGraphics2](https://github.com/temoki/TortoiseGraphics2) も
並べるのは、`Open Source` タグから来た層が実際に見に行くのがそちらだから。
First comment の "a turtle graphics engine in Swift" と "that engine"
（オンタリオの学校が授業で使ったもの）が指しているのもこのリポジトリで、
物語と成果物がリンクでつながる。

### Pricing

`Free`

### Funding information

`Bootstrapped` のみチェック。設問の定義が "Have not raised VC funding" なので
無料アプリでも該当する。Y Combinator / Venture backed は事実として該当しない。

---

## Shoutouts（Built with）

作るのに使ったプロダクトを挙げる欄。挙げたものは**その相手のレビューページに
「開発者レビュー」として残り、こちらへのリンクが付く**ので、ローンチ当日で
終わらない露出になる。Product Hunt 自身も「shoutout のあるローンチは featured に
なりやすい」と言っている。

### 何を挙げるかの基準

選ぶと追加で **「なぜ他ではなくこれを選んだのか」** と聞かれ、その答えが自分の
名前で公開レビューとして相手のページに残る。だから基準はひとつ。

> **その質問に、実際にした決定として答えられるか。**

「助けになったか」ではない。Product Hunt の文言自体は
*"products that helped make yours awesome"* と広いので、製品のコア実装で
ある必要はないが、答えが作り話になるものは挙げない。

| プロダクト | 判定 |
|---|---|
| **Xcode** | ⭕️ 3プラットフォームと Xcode Cloud |
| **GitHub** | ⭕️ 通信ゼロの主張は読めなければ宣伝文句、という実際の理由がある |
| **Claude Code** | ⭕️ 一人でこの規模を出荷する手段として最も効いた |
| Swift Playgrounds | ❌ **これで作っていない。** 2016年の前身エンジンの*配布形式*であって、このアプリのビルドには関係ない |
| SwiftUI Apps | ❌ フレームワーク本体ではなく「SwiftUI 製アプリの一覧」。レビュー対象が違う |
| Figma | ❌ ストアのスクリーンショットを組んだだけで、製品そのものではない |
| Blender | ❌ マスコットの3Dモデルだけ。同上 |

Swift は候補から選択できない。SF Symbols と Xcode Cloud は Product Hunt に
ページがない（404）。

**3本。**Figma と Blender は一度は候補に残したが外した。どちらも事実ではある
ものの、作ったのはストアのスクリーンショットとマスコットの3Dモデルであって、
製品そのものではない。数を増やすために挙げるものではない。

Claude Code は「AI で作った子ども向けアプリ」と読まれる余地があるので一度は
見送ったが、入れる。**書き方で対処する。**設計の判断は issue で先に決着させて
いて自分のものだ、という事実をレビュー文の中に置き、道具が効いたのは「一人で
この規模を出荷できたこと」だと書く。曖昧に濁すより、順序をはっきりさせたほうが
強い。

### レビュー文

**What made you choose Xcode over the alternatives?**

```
There isn't really an alternative, and that is worth saying plainly rather than
dressing it up as a decision. What Xcode earns its place with is range: one
project builds Tortoise Blocks for iPad, macOS and Apple Vision Pro, a QuickLook
thumbnail extension rides along in the same file, and pushing a git tag has
Xcode Cloud archive all three and send them to TestFlight without a build
machine of my own. For one person that is a release pipeline for free. The part
I would warn a newcomer about is how quietly it fails — a build setting that
resolves correctly and is then dropped from the generated plist, a mistyped
object id that unlinks a target rather than erroring — so check things in the
built product, not in the project window.
```

**What made you choose GitHub over the alternatives?**

```
Because the privacy claim only counts if you can check it. Tortoise Blocks says
it contains no networking code at all, and for a children's app that is either
verifiable or it is marketing — so the app is MIT on GitHub, where a parent or
a teacher can actually go and look. The rest is the ordinary reason: Actions
checks every pull request on three platforms, Releases carry the builds, the
website itself is Pages, and the issues are where a feature gets argued out
before it is written. One place, and free for a public repository.
```

**What made you choose Claude Code over the alternatives?**

```
Because the hard part of this project was never typing the code. Tortoise
Blocks is one person's app on three Apple platforms, with a document format
that is frozen — a file saved by the first release still has to open — and most
of its real work is decisions whose reasons are invisible in the code they
produce. Why the recursion limit is 30 rather than 100, for one: it was
measured, not chosen. Expansion overflows a 512KB stack between 55 and 60
levels deep in a debug build, and that is a crash, not an error you can catch.

What made me stay with Claude Code is that it works from the whole repository
and from a written record of those reasons — a CLAUDE.md that says why things
are the way they are — rather than from whichever file happens to be open. The
design is argued out in the issues before anything is built, and it stays mine.
What I get back is scope: an app this size, on three platforms, with the store
listing, the website and the capture rigs around it, is more than one person's
evenings otherwise.
```

## First comment

投稿直後に自分で書き込む本文。PH で一番読まれる場所。

```
Hi Product Hunt 👋

In 1994, in my second year of junior high school in Japan, a computer class
sat me in front of a Fujitsu FM R-50 running LogoWriter 2. There was a turtle
on the screen, and it left a line behind it wherever it walked. I got carried
away, my classmates crowded around the machine, and that was the first time I
ever succeeded at programming. It's the reason I write software for a living.

Seymour Papert, who designed Logo in 1967, died on 31 July 2016. That week I
started building a turtle graphics engine in Swift, so a kid could have on an
iPad what I'd had on that FM R-50.

Here's the part I actually care about. A boarding school in Ontario wrote to
say they were teaching with that engine, and their course ran in a particular
order: blocks first, then text, then each student plotted a shape of their own
on a pen plotter. That order is the design of this app. A child snaps blocks
together, and the pane right next to them shows the very same program as real,
syntax-colored Swift, ready to copy out. Blocks and code aren't two things here
— they're one program in two notations. The app is built for the day a child
outgrows it.

The rest: repeat, if, and boxes; dice in any number *or color* slot, so the
same program draws a different picture every run; and blocks you name yourself
— which can call themselves, so nine blocks on one screen draw a fractal tree.
Playback highlights the block being drawn, so it's never a mystery which block
made which line. Drawings are ordinary documents that show their own picture as
their icon; export SVG or PNG. iPad and Mac to build, Vision Pro to put the
finished drawing on your table.

No accounts, no ads, no analytics — there is no networking code anywhere in the
app at all. Free, and MIT on GitHub.

I'd love to hear what your kids draw with it.
```

事実関係は [site/why.html](../../site/why.html) と一致させてある（Papert の没日、
1994年の FM R-50 と LogoWriter 2、オンタリオの学校の授業順）。

**学校名は伏せたままにする（決定）。** 実名（Lakefield College School）を出すには
先方の許諾が要るし、話の力は学校名ではなく授業の順番のほうにある。
"a boarding school in Ontario" で十分伝わる。

---

## ギャラリー

画像は [gallery.html](gallery.html) が原稿で、[build.sh](build.sh) が
headless Chrome で撮って 1270x760（Product Hunt のギャラリー標準サイズ）に
落とし、oxipng にかける。文言や切り抜きを直すなら gallery.html を編集して
`./docs/product-hunt/build.sh` を走らせ直す。

| # | ファイル | 内容 | 元にしたキャプチャ |
|---|---|---|---|
| 1 | [1-blocks-to-swift.png](1-blocks-to-swift.png) | One program, in two notations | macOS `3_spiral_code` |
| 2 | [2-calls-itself.png](2-calls-itself.png) | A block that calls itself | iPad `4_tree_canvas` |
| 3 | [3-watch-it-draw.png](3-watch-it-draw.png) | Which block drew which line | iPad `2_spiral_canvas` |
| 4 | [4-on-the-table.png](4-on-the-table.png) | Off the screen, onto the table | visionOS `1_star_table` |
| 5 | [5-nothing-collected.png](5-nothing-collected.png) | It asks the child for nothing | （文字だけのカード） |

1枚目だけレイアウトが違う。左に文言・右に画面という他の並びのままだと
**コードペインの文字が読めない大きさにしかならず、訴求軸そのものが伝わらない**ので、
文言を上に置き、パレット列とウインドウ枠を捨てて、ブロックの列とコードの列だけを
切り抜いて大きく見せている。切り抜き枠の座標は gallery.html の `.crop` のコメントに
書いてある。

3枚のプラットフォーム（Mac / iPad / Vision Pro）が1〜4枚目に散らしてあるので、
機種の説明を文言に足す必要はない。

### Thumbnail（240×240）

[thumbnail-240.png](thumbnail-240.png)。[site/icon-256.png](../../site/icon-256.png)
を縮小しただけ。build.sh が一緒に作る。

### Video

既存の YouTube 動画 `https://youtu.be/b2wOul8UPWA` をギャラリー先頭に置く。
ランディングページのヒーローと同じもの。

### 既知の粗

iPad のキャプチャはステータスバーの日付が日本語（`8月20日(木)`）のまま。
App Store の en-US リストに出ているものと同じなので直さず使っているが、
英語圏向けの素材としては本来おかしい。直すなら `screenshots` skill の
撮り直しからで、この画像だけの問題ではない。

## 公開タイミング

Product Hunt の1日は **00:01 PT 固定**。

- PDT 期間（3月〜11月）: 日本時間 **16:01**
- PST 期間（11月〜3月）: 日本時間 **17:01**

つまり「今日出す」は「今日の 16:01 に始まる枠を取る」という意味になる。
16:01 より前に投稿すると前日の枠の残り時間に落ちるだけなので、そこは間違えない。
枠は1か月先まで予約できる。

### 曜日

平日と週末では、上位に入るのに必要な票数が違う。

| | 土曜 | 水曜 |
|---|---|---|
| Top 5 に入る中央値 | 266 points | 360 points |

土曜のローンチ数は水曜の約1/3で、必要な票が 35% 低い。ローンチリストも SNS の
地盤もない個人開発者にとっては、票の絶対数より**バッジが取れる確率**のほうが
効くので、週末は不利どころか有利に働く。

ただし **Product Hunt は金曜と土曜のローンチについては "Top products" の
ニュースレターを送らない**。週末の低い足切りを取りつつニュースレターも届くのは
**日曜**。

### 決定（予約済み）

**2026年9月13日（日）16:01 JST 開始の枠**（Product Hunt 上では Sunday,
September 13, 2026）。**2026-09-12 にフォームから予約済み。**日本時間の日曜夕方から月曜未明までが票の動く最初の8時間に
あたるので、張り付いていられる。

土曜を選ばなかったのはニュースレターが出ないから、平日（火曜）を選ばなかったのは
必要な票が 35% 上がったうえで AI プロダクトの物量と正面からぶつかるため。

### 当日の手順

1. 16:01 JST に枠が開く。開いたらすぐ **First comment を自分で投稿する**
   （上の全文をそのまま貼る）。ここが一番読まれるので、無言の時間を作らない
2. リンク4本が正しく開くか、実際に踏んで確認する。特に Website の `?lang=en`
3. ギャラリーは YouTube 動画 → 1〜5枚目の順。サムネイルは 240x240
4. コメントが付いたら返す。Product Hunt はメイカーの応答量そのものを見ている
5. 翌 16:01 JST に枠が閉じる。順位とバッジはそこで確定

## なぜこのアイデアに取り組んだのか

**Connect with Investors の欄は空のまま出す。** 投資家とつながりたいわけでは
ないので、埋める理由がない。

ただしその設問のうち "Why did you pick this idea to work on?" の答えだけは
書いておく。ローンチ当日にコメントで最もよく来るのが "why did you build this?"
で、First comment は経緯（1994年 → Papert → オンタリオの学校）を語っている一方、
**なぜタートル・グラフィックスでなければならないのか**という仕組みの話には
踏み込んでいない。そこを聞かれたときの答えがこれ。

そのまま返信に貼れる。

```
I did not pick it so much as fail to put it down for thirty years.

Turtle graphics was never a drawing toy. It was an argument, and the person
making it was Seymour Papert, who spent five years in Geneva working with Jean
Piaget on how children's thinking develops before designing Logo in 1967 around
what he later called constructionism: that children learn best while building
something real, something that works, that they can show to somebody, and that
fails in ways they can see and fix.

The mechanism is the part I care about. Almost all computer drawing is done
from a bird's-eye view — you look down at the page, name a coordinate, and draw
a line to it. From up there, an equilateral triangle needs trigonometry to find
where its third corner lands. From the tortoise's back it needs no mathematics
at all: three walks and three turns, and a child can see why. And when the turn
is wrong, the drawing says so at once — put 100 where 120 belongs and the
triangle does not close. So the child changes the number and runs it again, and
again, and somewhere in there stops guessing and starts knowing. That loop is
not a side effect of turtle graphics. It is the whole method.

What turned that from nostalgia into an app was the course order a school sent
me: blocks first, then text. Every block-based tool I know of is a cul-de-sac —
the child outgrows it and starts over somewhere else, or stops. So here the
blocks and the generated Swift are one program shown two ways, side by side. It
is built for the day a child outgrows it, which is the day most of these tools
quietly stop being useful.
```

## 残作業

- [x] ギャラリー画像5枚を 1270×760 で作る
- [x] Thumbnail 240×240 を書き出す
- [x] First comment の学校名をどうするか決める → 伏せたまま
- [x] 投稿フォームで launch tags の実際の補完候補を確認する → 3つとも存在した
- [x] 公開日を決める → 2026年9月13日（日）16:01 JST
- [x] Shoutouts に Claude Code を入れるか決める → 入れない
