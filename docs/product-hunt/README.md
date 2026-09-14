# Product Hunt 投稿内容

2026年9月13日（日）16:01 JST の枠に予約済み。`docs/` は公開されないので、
ここは作業用のメモ。

## 入稿フィールド

| 項目 | 値 |
|---|---|
| Name | `Tortoise Blocks` |
| Pricing | `Free` |
| Funding | `Bootstrapped` のみ |
| Launch tags | `Kids` · `Education` · `Open Source` |
| Product category | `Engineering & Development` > `Code editors`（1つだけ） |
| Website | `https://temoki.github.io/TortoiseBlocks/?lang=en` |
| App Store | `https://apps.apple.com/app/id6798677334` |
| GitHub（アプリ） | `https://github.com/temoki/TortoiseBlocks` |
| GitHub（エンジン） | `https://github.com/temoki/TortoiseGraphics2` |

Website の `?lang=en` は必須。付けないと閲覧者の環境次第で日本語で開く。

`Kids` の breadcrumb は `Kids & Parenting > Kids`。同名の親グループと
`Parenting` が補完に混ざる。

Launch tags はローンチに、Product category はプロダクトページに付く別の分類。
後者の選択肢は技術寄りの18項目しかなく、公開サイトの browse 分類にある
`Family` や `Education & Learning` は選べない。Launch tags 側で誰のためかは
伝わるので、こちらは「何であるか」を担当させる。枠は3つあるが埋めない。

### Tagline（60字以内 / 46字）

```
Block coding for kids that grows up into Swift
```

### Description（260字以内 / 256字）

```
Snap blocks into a program, press play, and a tortoise draws your picture line by line — while the pane beside it shows the same program as real, syntax-colored Swift. Blocks you name can call themselves, so nine of them draw a tree. iPad, Mac, Vision Pro.
```

## First comment

枠が開いたらすぐ自分で投稿する。PH で一番読まれる場所なので、無言の時間を作らない。

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

学校名は伏せたまま。実名を出すには先方の許諾が要る。

## Shoutouts（Built with）

Xcode / GitHub / Claude Code の3本。それぞれ「なぜ他ではなくこれを選んだのか」を
聞かれ、答えは自分の名前で相手のレビューページに公開される。

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

## ギャラリー

[gallery.html](gallery.html) が原稿、[build.sh](build.sh) が撮影・縮小・最適化。
文言や切り抜きを直すなら gallery.html を編集して `./docs/product-hunt/build.sh`。

| # | ファイル | 元にしたキャプチャ |
|---|---|---|
| 1 | [1-blocks-to-swift.png](1-blocks-to-swift.png) | macOS `3_spiral_code` |
| 2 | [2-calls-itself.png](2-calls-itself.png) | iPad `4_tree_canvas` |
| 3 | [3-watch-it-draw.png](3-watch-it-draw.png) | iPad `2_spiral_canvas` |
| 4 | [4-on-the-table.png](4-on-the-table.png) | visionOS `1_star_table` |
| 5 | [5-nothing-collected.png](5-nothing-collected.png) | （文字だけのカード） |

Thumbnail は [thumbnail-240.png](thumbnail-240.png)。動画は
`https://youtu.be/b2wOul8UPWA` をギャラリー先頭に。

iPad のキャプチャのステータスバーは、撮影ロケールの言語で撮影日の日付が入る
（`Tools/ipad-shots.rb` がシミュレータの言語を切り替えて撮る）。

## 当日

1. 16:01 JST に枠が開く。すぐ First comment を投稿する
2. リンク4本を実際に踏んで確認する
3. コメントには返す
4. 翌 16:01 JST に枠が閉じ、順位とバッジが確定

Connect with Investors は空のまま出す。

「なぜ作ったのか」を聞かれたときの返信。First comment が経緯なのに対して、
こちらは仕組みの話。

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
