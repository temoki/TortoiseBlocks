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

# visionOS. `-TBPlace` is the only way in: simctl sends no input, so without it
# the run is a window of buttons nobody can press. It does NOT show the drawing
# (see the tortoise note below) — it is for the load path, the USDZ, and the
# program/code windows.
xcrun simctl install <device> ~/Library/Developer/Xcode/DerivedData/TortoiseBlocks-*/Build/Products/Debug-xrsimulator/TortoiseBlocks.app
xcrun simctl launch <device> space.hiraku.tortoiseblocks -TBPlace YES

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
`BlockTree.usedVariableNames` / `renamingVariable` switch exhaustively too, so
a kind that mentions a name has to say so there. The compiler only forces the
exhaustive switches — do not skip the rest.
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

**A block the child defines is a name too** (#14, schema version 3). `define`
is a container carrying a name, `call` runs that name's body inline, and the
whole thing follows the variables' philosophy: a block exists exactly while
something mentions it (`BlockTree.usedFunctionNames` / `functionDefinitions`),
a call to a name nothing defines is a **no-op** rather than a broken reference,
and **the first definition of a name wins** — one answer shared by the expander
and the code generator, so the code pane can't describe a program that doesn't
run. Expansion is **two passes**: definitions are collected from the whole tree
(nested ones included) before anything runs, so a call may sit above the block
it calls, and `SwiftCodeGenerator` hoists each `func` above the program for the
same reason. Reaching a definition draws nothing and charges one step; a call
charges one and splices the body in, which is what makes recursion — the point
of the feature — fall out for free. Highlighting therefore lights the
*definition's* rows during playback, never the call, exactly as set/add and the
if test emit nothing. Version 3 is a real bump rather than another rider on 2:
2 has shipped, and a released decoder meets `{"define":…}` as an unknown
top-level key and rejects the whole document, so only the version number can
tell it the file is from the future. Renaming from the definition's header
renames **every call** with it (`WorkspaceEditor.renameFunction`) — the
alternative silently unhooks each call from the block it names — while a call's
own chip retargets that one call.

**The nesting limit is measured, not chosen** (`BlockExpander.defaultNestingLimit`,
30). Inlining a call recurses on the Swift stack, and the step cap cannot stand
in for that: in a **debug** build on a 512KB stack — any caller that isn't the
main actor, which includes every test in this package — expansion overflows
between 55 and 60 levels, a crash rather than an error (release clears 200), so
the design comment's original 100 was reachable from a block that calls itself.
It counts *every* descent, bodies and mouths as well as calls, because that is
what the stack counts: a definition wrapping its own call in five repeats spends
six frames per call, and bounding calls alone would have left the crash exactly
where it was. Re-measure before raising it — the regression test ("runaway
recursion throws instead of overflowing the stack") fails by killing the test
process, not by reporting.

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
`TARGETED_DEVICE_FAMILY` is `"2,7"` — iPad, Mac and Vision Pro, no iPhone
(#29, #11).
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
(`CODE_SIGN_IDENTITY = "-"` on macOS for both targets). Note *on macOS* — the
identity is `[sdk=macosx*]`-conditional, and it has to be written that way
round. The extension had it as a bare `CODE_SIGN_IDENTITY = "-"` with an
`[sdk=iphoneos*]` exception naming a real certificate, which reads the same
until a platform arrives that the exception doesn't name: a visionOS *device*
build then fell into the ad-hoc default and stopped with "has entitlements
that require signing with a development certificate" (both targets are
sandboxed, so ad-hoc is never enough on a device). Simulators hid it, because
they ad-hoc sign whatever they are given. Name the platform that wants ad-hoc,
never the ones that don't — the same rule as `#if !os(macOS)` in
`PlatformModifiers`, and the same silent failure when it is inverted.
Release does not ad-hoc sign, and must not: those pins used to sit in Release too, which quietly made the
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

**visionOS runs the iPad app, not a port** (#11). `SUPPORTED_PLATFORMS` gains
`xros xrsimulator`, `XROS_DEPLOYMENT_TARGET` is 26.0, and the same three-pane
`NavigationSplitView` fills the window — the scene is regular width, so nothing
in the layout is platform-conditional and no ornament or volumetric anything is
declared. Both packages already shipped `.visionOS(.v26)`. What the platform
actually costs is the `#if`s, in both directions. **A guard written
`#if os(iOS)` stops applying** — it still compiles everywhere, so `LaunchScene`
(`DocumentGroupLaunchScene` is unavailable on *macOS* only) and the numeric
keyboard and touch targets in `PlatformModifiers` were silently dropped until
they were rewritten as `#if !os(macOS)`. And some UIKit-era API is genuinely
gone: `ToolbarSpacer` — the Liquid Glass grouping separator — is unavailable,
which is the only reason `CanvasToolbar` exists as a `ToolbarContent` type of
its own. That is also why CI builds visionOS: nothing else catches an `#if`
that quietly does nothing.
One layout constant *is* load-bearing here, though the layout itself isn't
conditional: visionOS has **no draggable split-view divider** — macOS and
iPadOS 26 both do — so the workspace column is stuck at its `ideal` for good
while the canvas takes the rest of a wide window. That is what set the ideal at
440; the measurement is in `App/Views/CLAUDE.md`.
One thing is known-missing rather than done: **`hoverEffect` crashes** there —
`.automatic` as well as `.highlight`, a `swift_release` segfault inside
SwiftUI's update of `PaletteEntryButton.body`, before a window appears — so
`pointerHover()` stays iOS-only and says so.

**The app icon comes from a second, differently-shaped source.** visionOS wants
a circular layered icon and Icon Composer writes only squares (plus watchOS
circles), so `AppIcon.icon` produces nothing for it —
`Assets.xcassets/AppIcon.solidimagestack` does, three
`.solidimagestacklayer`s (Front / Middle / Back) of 1024×1024 at the `vision`
idiom. The two carry the same name on purpose and do **not** collide:
`ASSETCATALOG_COMPILER_APPICON_NAME` is `AppIcon` for every platform and actool
routes by idiom, so the visionOS `Assets.car` gets a `SolidImageStack` and no
`IconImageStack`, iOS gets the reverse, and macOS still gets `AppIcon.icns`.
Check a change here in the *built* product rather than in Xcode — `assetutil
--info` on each platform's `Assets.car` — because a stack that never made it in
fails the same silent way a missing one does: the system's placeholder, which
looks like a plain app that hasn't been styled yet.

**The 3D tortoise is generated, not modelled** (#53).
`App/Resources/Tortoise.usdz` — the sprite the immersive space will draw with —
comes out of `Tools/tortoise-model/build_tortoise.py`, a Blender script whose
constants *are* the three-view drawing's measurements. It is checked in
alongside the script so no build step needs Blender. Four things about it are a
contract app code will assume, and the reasoning for each is in
`Tools/tortoise-model/README.md`: `upAxis = "Y"` with **forward at `-Z`** (the
model is authored Z-up and the exporter puts `rotateXYZ = (-90, 0, 0)` on the
root — wrong settings here are invisible until the tortoise drives sideways);
**total length exactly 1.0** with `metersPerUnit = 1`, normalised rather than
real-world because the canvas is a 0.2–2m gesture and the size is always
computed anyway; the **origin is the ground point under the shell's centre**,
the point it turns about, *not* the brush tip, so the drawn line trails behind
the animal; and the whole thing rides in `App/` as a synchronized-folder
resource, landing flat at `Contents/Resources/Tortoise.usdz` (verified in the
built bundle, the only way that works — see the nested-CLAUDE.md note above).
Blender rendering it proves nothing about RealityKit; `qlcheck.swift` in the
same directory runs it through Apple's own USD stack instead.
A fifth thing is a contract with the *room* rather than with app code: **every
material emits a third of its own colour**, because a `.mixed` immersive space
lights the model with the real room and a lamp-lit evening one drained the
pastels to mud (measured: luminance 39 of 255, gold reading brown — 111 with
emission, and the facets still step). Do not "fix" it as a PBR error, and do
not lighten the colours instead: those are sampled from the drawing, which is
the specification. The reasoning and the shell's second texture are in the
tool README.

**The tortoise on the table is drawn by us, and that took a library release**
(#53 Phase 3, TortoiseGraphics2 2.1.0). The sheet is still the app's own
`TortoiseCanvas` in a `ViewAttachmentComponent`; what changed is that it now
draws everything *except* the tortoise (`.tortoiseSprite(.hidden)`), and the
USDZ stands on the paper as a child of the sheet entity — so the pinch, twist
and drag it inherits for free, and its own transform only ever says where on
the page it is. Three upstream additions were needed and none of them had an
honest app-side substitute. `.hidden` is a property of the *view*, unlike
`hideTortoise()`, which records a command and would have followed the drawing
into the SVG, the PNG, the thumbnail and the saved file.
`TortoisePlayer.currentTortoiseState` is the pose **interpolated between
commands**: `currentCommandIndex` — what every other surface in the app watches
— changes about ten times a second, and a tortoise moved on that schedule
teleports from command to command while the line it is drawing grows smoothly
underneath it, which is the one thing this feature exists to show. And
`ViewportMode.transform` is public so the placement asks for `autoFit`'s
mapping rather than reimplementing it; a reimplementation agrees on the day it
is written and drifts silently after. It is read once per *display frame*, from
a `SceneEvents.Update` subscription — not from `body`, which would re-evaluate
the view at the refresh rate — and the subscription has to be retained
(`FrameTicker`), because one that nothing holds is cancelled at the end of
`make` and looks exactly like a handler that is never called.
Two numbers are judged on device and are the first things to change if it looks
wrong: the tortoise is `1/12` of the sheet's side (deliberately larger than the
2-D sprite's ~1/30 — on a screen it is a cursor, on a table it is the animal),
and the paper keeps a 64pt margin, since a hidden sprite earns no `autoFit`
inset and the drawing would otherwise run to the paper's edge with the tortoise
hanging off it. The lift onto the paper is *measured* from the loaded model,
not assumed: the feet reach ~6‰ of the body length below the origin, which is
the ground point under the shell's centre.
**The visionOS simulator cannot check any of this.** It does not host
`ViewAttachmentComponent` views at all — the sheet's own `.task` never runs, so
`TortoisePlayer` never attaches to a canvas and `currentTortoiseState` stays
nil, which reads exactly like a broken tortoise. What the simulator *is* good
for is the two things that would otherwise be guesses: that the USDZ loads in
the real visionOS runtime with the bounds the contract promises, and that the
per-frame subscription fires. Everything else is the headset.

**The viewer has three surfaces, and the third is the code** (#53 Phase 3).
Table, program, code — a `WindowGroup` each, all open at once. That is the
whole argument for the platform restated one step further: iPad and Mac make
the canvas and the code two states of *one toggle* because a window holds one
of them, and a headset never has to choose. The code window is `CodePane`
unchanged, which #11 had already made work here by taking it off
`.background.secondary` (translucent glass on this platform, with the syntax
colours left standing on nothing). The source is generated in
`ViewerModel.load` rather than in the window's `body`: the iPad's pane is only
in the hierarchy while its toggle says so, but a window redraws on its own
schedule and nothing here can edit the program behind it.
**The remote's controls are grouped by what they do, not by what they are.**
The row used to read 「つくえに おく」「ブロックを みる」「コードを みる」, whose
only shared property was being buttons — one placed the drawing, two opened
windows — while placement's own mode switch and reset sat in a *different* row
underneath with those two wedged between. Placement is now one group with its
own question over it, the other surfaces are another below a divider, and three
things fell out of doing it. The two verbs went: 「つくえに おく」 (put the
drawing down) and 「つくえに のせる」 (look for a table at all) were nearly the
same words for different things, invisible while they sat apart and unbearable
once grouped — so `ViewerModel.placing` names the **three** states the window
actually has (away / table / in front) and one picker asks them. It stays
read-only and the window drives it through an async action, because `isPlaced`
is only true once the space has really opened and a refused world-sensing prompt
must leave the picker showing where the drawing *is*. A visionOS **ornament** was the other candidate for those
two — the platform's own place for "belongs to this window but is not its
content" — and was turned down: it is always visible, so it hangs under the
window even in the small "えが ありません" state and adds its height to every
glance, and a divider already says the difference for nothing. The window
buttons became toggles, since `openWindow` on an open window only brings it
forward — a switch with one position — so the windows report themselves through
`isProgramWindowOpen` / `isCodeWindowOpen`, there being nothing in SwiftUI to
read that from. And floating stopped being an error: it can now be *chosen*, so
`PlacementStatus` says "no table found" only when a table was actually asked
for.

**Opening a drawing puts it down**, and that is the placement group's last
open question answered. Choosing a file used to change nothing but the window:
the room stayed empty until the picker was touched, so the app read as one
that had not opened the file — the state with the least to look at was the one
reached by doing the thing the app is for. An alert asking "shall I put it on
the table?" was the obvious fix and is the wrong one twice over: the answer is
always yes, and the first placement already raises the world-sensing prompt, so
it would be two modals in a row before anything appeared. So a load *is* a
placement, through `ViewerModel.loadGeneration` — a counter rather than a flag,
because `blocks` cannot say "chosen again" when the same drawing is picked
twice, and because the five call sites (the importer and the four samples)
should not each have to remember. Where it goes is `sitsOnTable`, which is
therefore now a *remembered* preference rather than only the space's own
question: someone who has once said 「めのまえ」 is not asked again on the next
file. Nothing about it is a special case — the picker moves to wherever the
load put it, 「ださない」 takes it away, and a second file opened while one is
already out leaves the sheet exactly where it was dragged to, because `place`
sees the drawing is already there and returns.

**SVG/PNG export was built here and then taken back out**, and the reason is
worth keeping so it is not re-added as an oversight: it worked, and cost one
view — `CanvasExportMenu` unchanged, rendering `lastRunCommands`, so moving the
drawing into an immersive space changed nothing about what came out. It came
out because a viewer cannot change a drawing, so the file it was handed is
already the artifact, and writing a second one from it belongs where drawings
are *made*. The window is a remote control, and its row had reached four
buttons.

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
