# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
cd TortoiseBlocksKit && swift test        # Kit unit tests (fast, UI-independent)

# App builds (both must stay green):
xcodebuild -project TortoiseBlocks.xcodeproj -scheme TortoiseBlocks \
  -destination 'platform=macOS' -quiet build
xcodebuild -project TortoiseBlocks.xcodeproj -scheme TortoiseBlocks \
  -destination 'platform=iOS Simulator,name=iPhone 17' -quiet build

# Manual verification loop (macOS):
pkill -x TortoiseBlocks; open ~/Library/Developer/Xcode/DerivedData/TortoiseBlocks-*/Build/Products/Debug/TortoiseBlocks.app
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
  genuinely open UX forks (side-by-side options, ASCII mockups help), keep
  the design comment at policy level, then implement in two stages: a
  layout-only prototype commit → visual check in the running app (the
  pkill/open loop above) → polish (tests, a11y, both builds), then commit.
  Real widths, Dynamic Type, and touch targets are judged in the app, not
  in the document.

## Architecture

Two layers with a hard boundary:

- **TortoiseBlocksKit** — local SwiftPM package, depends only on
  `TortoiseCore`. Model (block tree + frozen JSON format + pure editing
  functions), Engine (`BlockExpander`), CodeGen (`SwiftCodeGenerator`).
  Everything here is unit-tested; UI iteration never touches logic.
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
`BlockCodableTests.kindFixtures`, the palette entry (`PaletteView`),
`SimpleBlockLabel` (`WorkspaceView`), and `App/Localizable.xcstrings`.
The compiler only forces the exhaustive switches — do not skip the rest.

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
so what's on screen is exactly what exports — including rolled dice. PNG is
rendered statically: a `speed(0)` tortoise makes `CanvasModel` flush all
frames at init, which is what lets `ImageRenderer` work without a live
timeline.

**Presentation modifiers clobber each other.** Attaching two `fileExporter`s
(or sheets/alerts of the same kind) to one view silently drops all but the
last. There is exactly one `fileExporter` with a dynamic content type.

**The canvas hides with `opacity`, not `if/else`,** when the code pane is
shown — destroying `TortoiseCanvas` would reset playback identity.

**Drop model**: a `DropGap` between rows carries `(containerID, index)`, so
insertion semantics need no y-coordinate math. Tap-to-add (with the repeat
header's "Add Here" toggle) is the accessibility alternative and must stay.

**Project file**: buildable folders (objectVersion 77) — files added under
`App/` need no pbxproj edits. Custom Info.plist keys (exported UTTypes,
document types) live in `Support/Info.plist`, merged via `INFOPLIST_FILE`.

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
