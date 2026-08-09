# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
cd TortoiseBlocksKit && swift test        # Kit unit tests (fast, UI-independent)

# Format / lint (config: /.swift-format, upstream-mirrored; Xcode 26's `swift format`).
# Note: `~/.swiftly/bin/swift-format` is a legacy binary that ignores the config —
# always use the `swift format` subcommand.
swift format --in-place --recursive App ThumbnailExtension TortoiseBlocksKit/Sources TortoiseBlocksKit/Tests
swift format lint --strict --recursive App ThumbnailExtension TortoiseBlocksKit/Sources TortoiseBlocksKit/Tests   # CI gate

# App builds (both must stay green):
xcodebuild -project TortoiseBlocks.xcodeproj -scheme TortoiseBlocks \
  -destination 'platform=macOS' -quiet build
xcodebuild -project TortoiseBlocks.xcodeproj -scheme TortoiseBlocks \
  -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' -quiet build

# Manual verification loop (macOS):
pkill -x TortoiseBlocks; open ~/Library/Developer/Xcode/DerivedData/TortoiseBlocks-*/Build/Products/Debug/TortoiseBlocks.app

# The App Store listing (appstore/). The check needs no key and no bundle;
# the other two need ASC_ISSUER_ID / ASC_KEY_ID / ASC_PRIVATE_KEY_PATH.
ruby fastlane/metadata_check.rb            # what CI runs on every pull request
bundle exec fastlane ios metadata_diff     # live listing vs what is written
bundle exec fastlane ios metadata_push     # upload (mac for the other listing)
```

## Issue Workflow

Issues tagged `needs design` get a design comment on the issue *before*
implementation; drop the label once the design settles, and wait for the
maintainer's "GoGo" to start building. Issue bodies and comments are
Japanese; commits are English with `Fixes #N`.

- **Model / wire-format / engine design** — write a full spec comment
  (仕様案 / やること / 受け入れ条件), the style of #12/#13. Wire-format
  changes must follow the frozen-format rules below, and say explicitly
  whether they ride the current schema version (pre-release only) or bump.
- **UI design** — don't settle pixels in prose. First confirm only the
  genuinely open UX forks, presented *visually* (an HTML mockup page styled
  like the app, or a prototype build — ASCII art is not enough), keep
  the design comment at policy level, then implement in two stages: a
  layout-only prototype commit → visual check in the running app (the
  pkill/open loop above) → polish (tests, a11y, both builds), then commit.
  Real widths, Dynamic Type, and touch targets are judged in the app, not
  in the document.

## Architecture

Two layers with a hard boundary:

- **TortoiseBlocksKit** — local SwiftPM package, depends only on
  `TortoiseCore`. Model (block tree + frozen JSON format + pure editing
  functions), Engine (`BlockExpander`), CodeGen (`SwiftCodeGenerator` plus
  `CodeTokenizer`, which spans the generated source for the code pane's
  syntax coloring). Everything here is unit-tested; UI iteration never
  touches logic.
- **App** — SwiftUI document app; depends on Kit + `TortoiseUI` +
  `TortoiseSVG`. Views are palette | workspace | canvas.

Runtime pipeline:

```
[Block] ──BlockExpander──▶ [ExpandedCommand] ──▶ Tortoise.apply ──▶ TortoiseCanvas(_:player:)
   │                              │
   └─SwiftCodeGenerator──▶ code pane            └─ blockID ──▶ executing-block highlight
```

## Key Design Decisions

**The JSON wire format is frozen.** `BlockKind` / `NumberValue` use
hand-written Codable with explicit coding keys (`repeatBlock` → `"repeat"`);
decode requires exactly one known top-level key (raw keys are counted so
unknown keys can't ride along) while unknown fields *inside* a payload are
tolerated for future extension. The fixtures in `BlockCodableTests` are the
document-format contract — breaking one breaks users' saved files.

**When adding a block kind**, update: `CodingKeys` + both switches in
`Model/Codable.swift`, `BlockExpander`, `SwiftCodeGenerator`,
`BlockKind.numberDomain` (`Model/NumberDomain.swift`),
`BlockCodableTests.kindFixtures`, the palette entry (`PaletteView`),
`SimpleBlockLabel` (`WorkspaceView`), and `App/Localizable.xcstrings`.
The compiler only forces the exhaustive switches — do not skip the rest.
Check the new SF Symbol against `BlockLabelStyle.widestSystemImage` too — the
rule and its silent failure are in `App/Views/CLAUDE.md`.

**All tree edits are pure functions** (`BlockTree`): they return a new tree,
or `nil` when the operation can't apply — callers treat `nil` as a no-op and
must not register undo for it. Undo is "swap back the previous tree".
Drag & drop moves are extract-then-insert, which makes dropping a block into
its own subtree safely impossible (the destination vanishes with the
extraction).

**Highlighting relies on index alignment.** `player.currentCommandIndex`
indexes `RunnerModel.expandedBlockIDs`; this only works because
`Tortoise.apply` records exactly the input stream, index for index (pinned
by the round-trip test in Kit). Never make `apply` emit extra commands.

**`WorkspaceEditor` is a value-type facade** over the `DocumentGroup`
binding + the environment `UndoManager`. Mutations register their inverse on
the *document's* undo manager, so dirty state, autosave, and ⌘Z follow
standard document behavior. UI state that must not be persisted
(insertion target) lives in `WorkspaceUIState`.

**Randomness rules**: a repeat *count* is evaluated once at expansion; values
in the *body* re-roll every iteration. Expansion is capped (10,000 steps)
and the overflow surfaces as a kid-friendly alert. Tests inject `SeededRNG`
for determinism.

**Numeric slots are bounded, and the bound belongs to the slot** —
`NumberDomain` (distance ±1000, angle ±360, pen width 0–100, repeat count
0–1000, general ±1000) is the single definition all three layers read.
*Input* refuses out-of-range values (the stepper stops at the bound; typed
text reverts to the last good value, the same path unparseable text already
took) so a bad literal never enters the tree. *Execution* saturates instead:
`BlockExpander` clamps every evaluated value and every arithmetic write-back,
because boxes drift past the bounds through `+=`/`*=` and dice bounds and
decoded documents never pass through the editor. *Storage* validates nothing
— the format is frozen, so out-of-range values load as written and saturate
only when they run. Dice clamp their *bounds*, not just the roll:
`Double.random(in:)` traps on a range too wide to represent, before there is
a result to clamp. Repeat counts convert through
`NumberDomain.iterationCount` — a bare `Int(Double)` traps outside `Int`'s
range and on inf/NaN — and the count cap is what bounds an *empty* repeat
body, which charges no step and so can never hit the 10,000-step limit
(#27: three crashes and a freeze, all reachable from ordinary editing).

**Variables are names, not registrations.** A variable ("box") exists
exactly while some block mentions it (`BlockTree.usedVariableNames`); unset
reads are 0, scope is a single global environment, and the same
once-per-count / every-iteration rules apply. The set/add blocks emit *no*
command — highlight alignment is untouched — but they still count against
the step cap, so assignment-only loops can't run away. The arithmetic
blocks (subtract/multiply/divide → `-=`/`*=`/`/=`) follow the same rules;
dividing by zero is a no-op — the box keeps its value, because inf/NaN
must never reach the tortoise. Documents are written
with `requiredSchemaVersion` (2 only when v2 features appear; otherwise 1,
byte-identical to the old format), and `BlocksDocument` probes
`schemaVersion` *before* the full decode so newer files fail with the
friendly "newer version" message instead of a generic decode error. The
preset names (🌟💖🍀) are SMP-plane emoji on purpose: like 🐢 they are valid
Swift identifiers in the generated code; BMP lookalikes (⭐ ❤️) are not.

**The if block shares schema version 2 with variables** (v2 never shipped
between them). Its condition is two `NumberValue` slots around a
`Comparison` (five operators, frozen raw strings), re-evaluated on every
encounter — dice in a condition re-roll, and that single evaluation picks
exactly one mouth. Like set/add, the test emits no command but charges a
step, so false-branch-only loops still hit the cap. `elseBody` is optional
*presence*: absent on the wire = no else mouth (byte-identical to the
pre-else shape), `[]` = mouth exists but empty — this payload extension was
only legal because v2 had never shipped; once a version is released, new
payload fields would be silently dropped by fielded decoders, so
post-release additions need a new wire key + schema bump. Sibling lists are
addressed by `BodyAddress` (container + `BodySlot`), so the else mouth is a
first-class drop/insertion target; container kinds stay uniform via
`BlockKind.containerBodies` / `body(for:)` / `replacingBody(_:with:)` — a
new container only adds its header UI (`ContainerBlockRow` in
`WorkspaceView`) and the exhaustive switches.

**Exports render `lastRunCommands`** (the evaluated stream of the last run),
so the exported drawing is the one that actually ran — including rolled
dice. But the export is *not* the on-screen framing (#25): the canvas pane
is a fill-the-pane working view with the tortoise cursor, while both exports
are the clean artifact — cropped tight to the drawing, tortoise-free.
PNG mirrors SVG's `fit: true`: `RunnerModel.pngData` sizes the
`ImageRenderer` frame to the drawing's bounding box (`DrawingBounds.compute`
/ `CommandPlayer.play`, both public in `TortoiseCore`) instead of a fixed
512×512 square, so it's pane-independent; `hideTortoise()` on the throwaway
export tortoise drops the sprite (`CanvasRenderer.drawTortoise` guards on
`isVisible`). Extreme aspect ratios clamp to 3:1 and an empty drawing falls
back to 512×512, matching SVG's no-visible-output fallback. PNG is rendered
statically: a `speed(0)` tortoise makes `CanvasModel` flush all frames at
init, which is what lets `ImageRenderer` work without a live timeline. (The
one gap: `.autoFit` always adds a small sprite-size inset, so PNG carries a
uniform safe margin where SVG is edge-to-edge — pixel parity would need an
upstream tight-fit mode, deliberately out of scope.)

**The document carries its own thumbnail, and nothing else** (#15). The Files
app's "Tortoise Blocks" folder *is* the gallery, so there is no in-app gallery
screen; what the system browser can't do on its own is tell 「ほし」 from
「うずまき」, hence `BlocksProject.thumbnail` — a PNG of the last run, long side
256pt, refreshed on every run. `JSONEncoder` writes `Data` as base64, and the
optional's *presence* is the compatibility story: nil writes no key, so a
document that has never run stays byte-identical to what earlier apps wrote and
this rides schema version 1. Do not confuse this with restoring the canvas
(#10, closed): the picture is metadata for the file browser, it is never read
back into the app, and reopening a document still starts empty. 256 is a
ceiling, not a guess — a thumbnail costs 3–51KB of base64, *the size follows
the ink rather than the command count* (the 10,000-command drawing is the
smallest one), and doubling it would quadruple that for a picture usually shown
at icon size. `RunnerModel.renderPNG` is shared with the PNG export, so a
thumbnail is framed like the exported artifact: cropped tight, tortoise-free.
It differs in exactly one way, and the difference is deliberate — **the
thumbnail is opaque, the exports are transparent**. `TortoiseCanvas` paints no
background of its own (temoki/TortoiseGraphics2#44), so a render comes out
transparent unless something is put behind it. That is right for an export,
which is a picture you place somewhere yourself, and wrong for a thumbnail,
which Finder and the Files app composite onto *their* background — against a
dark one a black-pen drawing on a transparent ground disappears, taking the
whole point of putting the picture on the file with it. Hence `onWhite`.
Writing it skips `registerUndo` — running is not an edit — while still
dirtying the document.

**The thumbnail extension knows nothing about blocks.** `ThumbnailExtension`
links no package at all: it decodes one `Data?` field out of the JSON with a
bare probe struct and draws it. That is why an unknown block kind or a
`schemaVersion` from a future release still gets a thumbnail, and why the
original plan's risk — running `ImageRenderer` inside an extension, or writing
a CoreGraphics renderer upstream — evaporated. Anything unreadable (no
thumbnail, corrupt JSON, corrupt PNG) returns `(nil, nil)`, which hands the
file back to the system's document icon; an extension must never be the reason
a file fails to display. One trap, and it is invisible without an end-to-end
check: `QLThumbnailReply(contextSize:drawing:)` documents its size in points
but hands back a context measured in device pixels with an identity CTM, so
drawing into a rect of `contextSize` fills a *quarter* of a 2× thumbnail and
parks it in a corner. Ask the context for its own `width`/`height` and map that
through `ctm.inverted()`. Verify with `QLThumbnailGenerator` against real files
(`qlmanage -t` tends to hang) — it loads the installed extension for real, and
it is what caught this.

**A nested CLAUDE.md inside a buildable folder ships inside the app** unless
it is excluded. `App/` is synchronized, so `App/Views/CLAUDE.md` was copied
straight into `Contents/Resources/` — the same way `Support/` would have
shipped `Local.xcconfig`, and just as silently, with the build at EXIT=0. It
is kept out by a `PBXFileSystemSynchronizedBuildFileExceptionSet` naming
`Views/CLAUDE.md`, hung off the app target. Verify a new one the only way that
works: build clean and look in the bundle.

**How the views look and behave is in `App/Views/CLAUDE.md`.** Block colour and contrast, row width and height, the container's C shape, the playback row, VoiceOver, the drop model, and the SwiftUI traps that go with them.

**Project file**: buildable folders (objectVersion 77) — files added under
`App/` need no pbxproj edits. Custom Info.plist keys (exported UTTypes,
document types) live in `Support/Info.plist`, merged via `INFOPLIST_FILE`;
the rest are `INFOPLIST_KEY_*` build settings, including the SDK-conditional
`UISupportsDocumentBrowser` an iOS `DocumentGroup` target has to declare
(`[sdk=iphoneos*]` / `[sdk=iphonesimulator*]` = YES, matching Xcode's own
template, so the macOS build never sees it — #33).
**Only some keys have an `INFOPLIST_KEY_*` form**, and the ones that don't
fail *silently*: `INFOPLIST_KEY_UIFileSharingEnabled = YES` resolves as a
build setting and shows up in `xcodebuild -showBuildSettings`, but the
generated-plist step honors a fixed set of names and drops it, so the key
never reaches the bundle. Verify a new key in the *built* plist (`plutil -p`
on the product, and in a clean build directory — the plist step won't rerun
for a setting it doesn't consume). `UIFileSharingEnabled` therefore lives in
`Support/Info.plist`, where it is shared by both platforms rather than
SDK-conditional: `INFOPLIST_FILE` takes one path, splitting it would
duplicate the UTType declarations, and macOS simply ignores an iOS key. It
is what puts a "Tortoise Blocks" folder under On My iPad in the Files app —
the app's own directory *is* the gallery, which is why no in-app gallery is
planned (#15).
The QuickLook extension is a second target in the same hand-written project
(#15): its own buildable folder `ThumbnailExtension/`, `NSExtension` keys in
`Support/ThumbnailExtension-Info.plist`, and a `dstSubfolderSpec = 13` copy
phase on the app that embeds the `.appex`. Two things it needs that are easy to
miss. Object IDs here are hand-assigned 24-character strings — a 25-character
typo does not fail the parse, it silently unlinks the object, and the symptom
is a target that builds with *default* settings ("Cannot code sign because the
target does not have an Info.plist"; check with `xcodebuild -target … -showBuildSettings`).
And a macOS QuickLook extension has to be sandboxed to be loaded, so it carries
`Support/ThumbnailExtension.entitlements` (`com.apple.security.app-sandbox`)
even though the app itself has none. `pluginkit -mAvvv | grep -i tortoise`
confirms registration — the `-p com.apple.quicklook.thumbnail` filter does not
match it and will make a working extension look missing.
`TARGETED_DEVICE_FAMILY` is `"2"` — iPad and Mac, no iPhone (#29).
Documents are `.tortoise` files, but the exported UTI keeps the
`tortoiseblocks` spelling (`space.hiraku.tortoiseblocks.project`, and
`.block` for the drag payload), which is also the bundle ID's — the
extension is what users see, the identifiers are what the system matches on,
and they differ on purpose. Don't "fix" one to look like the other.
Don't explain anything *inside* `Support/Info.plist`: Xcode rewrites that
file whenever the project changes, dropping comments and alphabetizing each
dict's keys. A diff that is only that reshuffle is Xcode's, not an edit —
check it parses the same (`plutil -convert json` on both revisions) and
commit it rather than reverting it back and forth.
`Support/` is a plain group, deliberately **not** a buildable folder like
`App/` and `ThumbnailExtension/`, and converting it in Xcode (one click, and
tempting for consistency) breaks two things at once — both silently, with the
build still at `EXIT=0`. Its contents are the opposite kind of file: they
never enter a build phase, they are *named by build settings*
(`INFOPLIST_FILE`, `CODE_SIGN_ENTITLEMENTS`, `baseConfigurationReference`),
which is exactly what synchronization cannot express.

*The xcconfig stops applying.* `baseConfigurationReference` has to point at a
real `PBXFileReference`, and a file inside a synchronized group has none — so
Xcode deletes `Signing.xcconfig`'s reference on conversion and takes the
`baseConfigurationReference` with it. `DEVELOPMENT_TEAM` then resolves to
nothing and signing quietly reverts, the same failure shape as the
25-character object ID. Keeping an orphan reference to dodge this does not
work either: `<group>`-relative, it loses the `Support/` prefix and points at
the project root. (`sourceTree = SOURCE_ROOT` with a full path does resolve —
and is exactly the kind of unparented object Xcode prunes on its next
rewrite.)

*And `Support/` ships inside the app.* Attached to a target, the folder's
files are copied into the bundle as resources: measured on a clean build,
`Contents/Resources/` came out holding `Signing.xcconfig`,
**`Local.xcconfig` — the gitignored file, Team ID readable straight out of
the product** — `ThumbnailExtension-Info.plist`, and a duplicate of
`Info.plist`. Keeping the team out of the repository is pointless if the
build puts it in the app. (`.entitlements` is excluded by file type;
`.plist` and `.xcconfig` are not.) A
`PBXFileSystemSynchronizedBuildFileExceptionSet` naming every file would stop
the copying, but nothing fixes the first problem, so the exception machinery
buys a folder that still cannot carry the xcconfig.

**The signing team never enters the repository** (#4). A Team ID is not a
secret — it sits in every distributed app's embedded provisioning profile —
but a fork that inherits someone else's team meets signing errors it has no
way to fix. `DEVELOPMENT_TEAM` therefore lives in `Support/Local.xcconfig`,
gitignored, pulled in by an optional `#include?` from the committed
`Support/Signing.xcconfig`, which is the *project-level*
`baseConfigurationReference` and so reaches both targets from one place. CI
greps `project.pbxproj` for the setting, because a build setting cannot
enforce its own absence and Xcode writes one there the moment a team is
picked in Signing & Capabilities.
The everyday loop needs no team because **Debug ad-hoc-signs**
(`CODE_SIGN_IDENTITY = "-"` on macOS for both targets). Release does not, and
must not: those pins used to sit in Release too, which quietly made the
distribution configuration unable to archive at all — an ad-hoc macOS app
cannot go to App Store Connect. Release is left to automatic signing, which
is what Xcode Cloud's cloud signing then takes over; that is the whole reason
release builds go through Xcode Cloud rather than the GitHub Actions CI,
which only ever builds Debug with `CODE_SIGNING_ALLOWED=NO`.
**Both targets are sandboxed**, and the app's entitlements are not optional
polish: macOS TestFlight ships through App Store Connect, so Mac App Store
rules apply. The app takes `files.user-selected.read-write` for the
`DocumentGroup`'s open/save panels and the exporter; the extension keeps
`read-only` and is sandboxed for a different reason (a macOS QuickLook
extension is not loaded otherwise).

**Releasing, the store listing and the website are in the `release` skill.** Tags, Xcode Cloud, TestFlight, `appstore/`, fastlane, and `site/`.

**Localization**: `en` is the source language; Japanese (kid-friendly
hiragana) lives in `App/Localizable.xcstrings`. Palette titles are
`LocalizedStringResource` — a plain `String` there would silently bypass
localization.

**Upstream-first.** TortoiseGraphics2 is our own library, exact-pinned in
both `TortoiseBlocksKit/Package.swift` and the Xcode project (keep the two
requirements identical). When a library limitation forces an app-side
workaround, prefer fixing it upstream (precedent: issues #23–#25 became
`TortoisePlayer`, `reset()`, and command `Codable`).

## Testing

swift-testing (`@Suite` / `@Test` / `#expect`) in
`TortoiseBlocksKit/Tests/`. Suites that touch `Tortoise` are `@MainActor`.
The JSON fixtures in `BlockCodableTests` are a frozen contract (see above).
`SeededRNG` (SplitMix64) makes expander randomness deterministic.
