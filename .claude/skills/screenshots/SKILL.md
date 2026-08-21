---
name: screenshots
description: >-
  Producing every picture of the app that ships: the App Store captures in
  appstore/screenshots/ for iPad, Mac and Vision Pro, and the downscaled copies
  the website uses in site/shots/. Covers the capture rigs
  (Tools/ipad-shots.rb, Tools/visionos-shots.rb), the flatten-and-optimise pass
  (Tools/screenshots.rb), what a sendable capture has to be, and the traps that
  make a screenshot tool fail silently. Load this before reshooting, before
  adding a shot or a platform, and whenever a capture looks wrong.
---

# Screenshots

Three platforms, two languages, one pass at the end. **Every route ends in
`ruby Tools/screenshots.rb`**, and a green `appstore/ looks sendable.` is the
only evidence that counts.

```bash
ruby Tools/ipad-shots.rb                 # iPad: 4 shots × 2 languages, ~8 min
ruby Tools/macos-shots.rb                # Mac: 4 shots × 2 languages
ruby Tools/visionos-shots.rb             # Vision Pro: 3 shots × 2 languages
ruby Tools/screenshots.rb                # always: strip alpha, optimise, rebuild site/shots
```

All three take a name filter (`ruby Tools/ipad-shots.rb star`) and end by
calling `Tools/screenshots.rb` themselves. Build the scheme first; they install
whatever is in DerivedData.

## What a capture has to be

`fastlane/metadata_check.rb` enforces all of this, on every pull request, from
the files alone — so the answer to "is this sendable" is to run it, not to
look.

- **Sizes**: iPad 13-inch 2752×2064 (or portrait), Mac 2880×1800, Vision Pro
  3840×2160. A size Apple does not accept is a mistake worth stopping on, not
  a shape to guess at, so an unexpected one fails rather than being resized.
- **No alpha channel.** App Store Connect refuses one and says so only when the
  submission is refused.
- At most ten per locale; order comes from the leading number in the filename.
- Directories are App Store Connect's own vocabulary — see the `release` skill,
  which owns the listing side.

## The flatten-and-optimise pass

**Every source this project shoots from writes an alpha channel and none can be
told not to**: the iPad and Mac captures come out of XCUITest, the visionOS
ones from `simctl io`. The channel has always been fully
opaque, so `Tools/screenshots.rb` drops it losslessly — `-alpha off`, never a
composite. A capture with *real* transparency stops the run instead, because
choosing a background would change the picture and that is a person's decision.

It then runs `oxipng -o max --strip safe`, which is lossless and worth about a
fifth of the bytes, and regenerates `site/shots/`.

**That last part is the reason it is a script and not a paragraph.** The site
images are downscaled copies of seven captures, so a reshoot that stops at
`appstore/` leaves the website showing the previous build's UI. That was missed
twice before the script existed.

Two things to expect. The site derivation is deterministic — rerunning it
against unchanged captures reproduces the committed files byte for byte, so a
no-op run leaves the tree clean. But `oxipng -o max` is *not* bit-for-bit
reproducible, so `--all` can rewrite an already-optimal capture by a few dozen
bytes with the pixels untouched; that is why the default run only touches what
it just flattened.

It asks `MetadataCheck.alpha?` about the channel — the same predicate the CI
gate uses, so the fixer and the gate cannot disagree about what counts.

### Adding a site image

`DERIVED` in `Tools/screenshots.rb` maps capture → site file and size. It is a
table rather than a rule because the choice is curated: the code pane is on the
Mac half of the page and not the iPad half. A new site image is a new row.
There is no visionOS row yet.

Quantizing to 256 colours is what makes the page ~1MB instead of ~4.7MB, and
flat app UI loses nothing visible — but check a re-quantized shot by eye, since
dithering *on* leaves visible speckle in toolbar shadows.

## iPad — a UI test, not launch arguments

`TortoiseBlocksUITests/ScreenshotTests.swift` does the pressing;
`Tools/ipad-shots.rb` holds the shot list and the plumbing.

**Rotation is why it is a UI test.** `simctl` cannot turn an iPad, and driving
the Simulator's own menu means granting keystroke permission to whatever runs
the script. `XCUIDevice` rotates in a line, and the same mechanism then presses
play and switches panes — so the app carries no screenshot-only code.

**Nothing matches on a label**, since both languages are shot from the same
code. What is stable is an element's type, its position, and — for the
transport — its **SF Symbol name**, which SwiftUI passes through as the
accessibility identifier (`play.fill`).

Five failures, each of which produces a capture that looks perfectly well made:

- **The scrubber is `Disabled` until a program has been run.** There is no
  shortcut to the end of a drawing: dragging it, `adjust(toNormalizedSliderPosition:)`
  and `⌘R` (`AppCommands`, and the simulator has no hardware keyboard) all do
  nothing, silently, and hand back a picture of an empty canvas. Tap `play.fill`
  and wait for the scrubber's accessibility value to stop changing.
- **`XCTAttachment(screenshot:)` writes the framebuffer as it is held** —
  portrait — and leaves the rotation to a flag, so a landscape capture arrives
  2064×2752 on its side. Redraw the image once to bake it in.
- **Set the orientation after `launch()`.** Before it, the device comes back
  portrait when the app arrives and the setting is silently undone.
- **`TEST_RUNNER_*` must be on xcodebuild's own environment.** Passed as
  `KEY=value` arguments after the command they are accepted, ignored, and
  arrive nowhere.
- **Seed documents into the device's `tmp`, not the app's container.**
  Preparing a run reinstalls the app, and a reinstall gives it a new data
  container, so anything seeded there beforehand is gone.

Two more the driver handles. The app is **uninstalled before each group of
shots**: opening a document from outside the app's own folder imports a copy
under a deduplicated name, against a history that outlives deleting the files,
so the spiral came back titled `spiral-1` in its own title bar. And shots are
**grouped so each drawing is opened once per run**. The status bar is pinned to
**9:41** for the run — without it the captures carry whatever the clock said,
and a reshoot never matches the set it joins.

Testing is non-parallel on purpose: a parallel run clones the simulator, and
the clone is not the device the documents were seeded on.

## Vision Pro — launch arguments

`-TBPlace` loads a sample and puts it down, `-TBSample` picks which,
`-TBDraw <0…1>` runs the drawing that far, `-TBSheet side,reach,drop` frames
it. Language comes from `-AppleLanguages` on the same line, so both locales
come out of one run with nothing left switched on the device.

- **The simulator shows the drawing.** A long-standing note said it hosts no
  `ViewAttachmentComponent`; it does. What was broken was placing *after* the
  load, which flips `sitsOnTable` — the `.id()` on the immersive space's
  `RealityView` — demolishing the scene at launch.
- **`-TBSheet` overrides `reach` and `floatingDrop`, not the position they
  produce.** The simulator reports a usable head pose, so placement takes the
  *aimed* branch exactly as a headset does; an override written against the
  no-pose fallback compiles, runs, and does nothing.
- **The sheet is nearer than the windows**, so a paper wider than about 0.7m
  occludes the blocks and code windows — which is the arrangement the captures
  exist to show. Treat `side` as a ceiling.
- The app is **uninstalled before every capture**: visionOS restores windows,
  so a launch otherwise inherits the last one's and opens its own on top —
  two blocks windows, one of them near the ceiling.
- A run occasionally opens with **no sheet at all**. The app logs `TBReady`
  once the canvas has attached, `TBNotReady` if it gives up, and the driver
  relaunches rather than photographing an empty room. Waiting on `EntityLoad`,
  which is only the USDZ arriving, files pictures of empty rooms.

## macOS — a UI test and a plate

`Tools/macos-shots.rb`, sharing `ScreenshotTests.swift` with the iPad. The
capture is the **window alone** (`XCUIElement.screenshot()`); the desktop and
menu bar around it come from `appstore/screenshot-sources/macos-plate-{en,ja}.png`,
drawn once per language. That is what keeps the picture independent of the
machine — no wallpaper, menu extra or clock of the Mac's own reaches it.

**The plates carry no shadow.** It is generated at composite time, so the
window can move or change size without the artwork being redrawn. The window
is centred under the menu bar and fully in frame.

**macOS UI testing needs Xcode to hold the Accessibility permission** (System
Settings ▸ Privacy & Security ▸ Accessibility). Without it every run fails
with "Timed out while enabling automation mode", which mentions neither Xcode
nor permissions.

Four ways the Mac differs from the iPad, all handled but all worth knowing:

- **The window screenshot is fully opaque, with the rounded corners filled
  near-black.** Composite it as-is and the window wears four black wedges. The
  corners are flood-filled to transparent rather than masked with a drawn
  radius — the shape is macOS's own continuous curve, not a circle.
- **macOS reopens the windows it had when it quit**, so the second shot's
  launch restores the first shot's drawing and opens its own beside it. Two
  windows means two transports, and `play.fill` stops being a single element:
  "Multiple matching elements found", which says nothing about restoration.
  Every window is closed after the launch.
- **The same `Picker(.segmented)` is a different element**: a
  `SegmentedControl` of buttons on iOS, a `RadioGroup` of radio buttons in the
  toolbar on macOS.
- **The saved window state is thrown away before each run.** macOS restores a
  window's frame in preference to the app's `defaultSize`, and that default is
  what makes 1280×800pt — 2560×1600px — reproducible. Keep that `defaultSize`:
  a capture at any other size would need cropping or resampling.

## Judging the result

Look at the pictures. `metadata_check` proves a capture is *sendable*, not that
it shows the right thing — every failure listed above passes it. The rigs
report what they filed; open the files.
