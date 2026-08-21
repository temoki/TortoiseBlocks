# The visionOS viewer

Everything in this directory is `#if os(visionOS)`. It is a different product
from the editor next door (#53): a viewer for drawings made on iPad and Mac,
with no editing in it at all — which is what lets the whole `DocumentGroup`
apparatus go, and is the reason a visionOS build is worth having instead of an
iPad app in a window.

The scene tree that ties these together is in `App/TortoiseBlocksApp.swift`;
how the editor's own views look is `App/Views/CLAUDE.md`.

**The 3D tortoise is generated, not modelled** (#53).
`App/Resources/Tortoise.usdz` comes out of `Tools/tortoise-model/build_tortoise.py`,
a Blender script whose constants *are* the three-view drawing's measurements, and
is checked in beside it so no build step needs Blender. **The reasoning for every
number is in `Tools/tortoise-model/README.md`**; what app code may assume is:

- `upAxis = "Y"` with **forward at −Z** — wrong settings here are invisible until
  the tortoise drives sideways.
- **Total length exactly 1.0** with `metersPerUnit = 1`. Normalised, not
  real-world: the canvas is a 0.2–2m gesture and the size is computed anyway.
- **The origin is the ground point under the shell's centre** — the point it
  turns about, not the brush tip, so the drawn line trails behind the animal.
- **Every material emits a third of its own colour.** A `.mixed` space lights the
  model with the real room, and a lamp-lit evening one drained the pastels to mud
  (luminance 39 of 255, gold reading brown; 111 with emission). Do not "fix" it as
  a PBR error, and do not lighten the colours — they are sampled from the drawing,
  which is the specification.

It rides in `App/` as a synchronized-folder resource, landing flat at
`Contents/Resources/Tortoise.usdz` — verified in the built bundle, the only way
that works. Blender rendering it proves nothing about RealityKit; `qlcheck.swift`
runs it through Apple's own USD stack instead.

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
**The visionOS simulator shows all of this** — paper, drawing and tortoise —
and this note said the opposite for a while, which is worth keeping as a
correction rather than an edit. The symptom was real: a blank sheet, a nil
`currentTortoiseState`, a tortoise that never appeared. The diagnosis was not.
`ViewAttachmentComponent` hosts fine here; what was broken is that `-TBPlace`
used to place by calling `place(.inFront)` *after* the load, which flips
`sitsOnTable`, which is the `.id()` on the immersive space's `RealityView` — so
the scene was torn down and rebuilt at launch and the attachment did not come
back. Setting the preference before the load (which is what "opening a drawing
puts it down" made natural) leaves the id alone and the sheet renders. The
lesson generalises: `.id()` on a `RealityView` is a demolition order, and an
attachment that fails to return from one is indistinguishable from a platform
that never supported attachments.
**Screenshots are shot from the simulator, not a headset** — a room cannot be
framed the same way twice and is someone's home besides. The rig, its launch
arguments and its traps are the `screenshots` skill. One thing here is app
code rather than tooling: `-TBSheet` overrides `reach` and `floatingDrop`,
the two constants the *aimed* placement is built from, rather than the position
they produce. The simulator reports a usable head pose (`queryDeviceAnchor`
starts at the identity transform, which is what `minimumEyeHeight` guards
against, but `pose` retries for three seconds and gets a real one), so
placement takes the aimed branch exactly as a headset does — and an override
written against the no-pose fallback compiles, runs, and does nothing.

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
**The three windows open beside each other, not on top** (#53). Left the
system, every window opens in the same place — straight ahead — so asking for
the blocks put them over the controls that asked, and asking for the code put
it over both. Three surfaces at once is the entire argument for this platform,
and stacking them is the one arrangement that does not deliver it, so the
program and code groups carry `defaultWindowPlacement`: blocks to the remote's
`.leading`, code to its `.trailing`, reading order deciding which side, since
the blocks are what the drawing is made *from* and the code is what they
become. The remote therefore has an id of its own (`remoteWindowID`) — unusual
for an app's first window, and the only way `WindowPlacementContext.windows`
can be asked which one to sit beside. On visionOS a placement can name another
window and a side and nothing else: every absolute initialiser is
`@available(visionOS, unavailable)`. That is exactly enough here, and it is
also why this was nearly written off as impossible — the App Store captures
were going to be shot around the overlap before the API was checked.

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

