# App/Views

How this app's views are meant to look and behave. These sit here rather than
in the root CLAUDE.md because the trigger is the directory: every rule below
is about code in this folder, and most of them break *silently* — a contrast
ratio nobody measures again, a row height that stays wrong exactly as if the
fix were missing, an accessibility element that reads three times instead of
once.

**The tortoise on screen is our artwork, not the library's triangle.**
`CanvasPane` sets `.tortoiseSprite(.image(...))` (TortoiseUI 2.0.0)
with the `TortoiseSprite` asset at its natural size, 23×32pt, so the
@1x/@2x/@3x renditions land pixel-exact at viewport scale 1; the library
scales it with the viewport from there, exactly as it scaled the triangle.
The asset must point **up** — `.image` rotates its top edge toward the
heading. Two consequences. The modifier is deliberately *not* applied to
the PNG export's throwaway canvas: `.autoFit` insets by the sprite's
half-diagonal × 2, which the triangle makes 20 and this artwork ~39, and
`RunnerModel.exportFrameSize` mirrors that constant to match SVG's framing
(the sprite is hidden there in any case). And a mascot is opaque where the
triangle was 70% — it covers the line it stands on while drawing, which is
the price of the artwork, not a bug to fix in the renderer.

**Presentation modifiers clobber each other.** Attaching two `fileExporter`s
(or sheets/alerts of the same kind) to one view silently drops all but the
last. There is exactly one `fileExporter` with a dynamic content type.

**The canvas hides with `opacity`, not `if/else`,** when the code pane is
shown — destroying `TortoiseCanvas` would reset playback identity.

**The playback row is a video transport** (#28): a scrubber, then rewind /
step back / centre / step forward / speed, all visible at once — no
disclosure, no clear button. The Run menu holds none either (#34): "Clear"
and the canvas's "Roll Again" (⟳) both left an empty canvas and differed
only in state no child tracks — a discarded command stream, exports switched
back off — so the menu now carries "Roll Again" itself (⇧⌘R), calling the
identical `run(_:startPaused: true)`. Same name, same result, wherever it is
pressed; it is enabled by the blocks, not by `commandCount`, because rolling
a *first* set of dice is exactly what it is for. "Empty the canvas" is
"Back to Start". The centre button is one control with four
meanings (`TransportAction`: run when the tree is stale, pause, play/resume,
replay), so the same position always answers "what happens if I press this";
`run` rolls fresh dice, `replay` redraws the identical stream. Two costs
shaped this row, both because it re-renders on *every committed command*.
Staleness is a hash of the block tree, and `CanvasPane` computes it and
passes it down rather than letting `PlaybackControls` hash on each redraw.
And the scrubber carries no `step`: `Slider` draws one tick per step and
redrawing costs faster than linearly in their number, while the range here
*is* the command count — 25ms per update at 1,000 commands against 0.35ms
with no step, paid ten times a second during playback. The
one-command unit the step used to give VoiceOver and the keyboard now comes
from `accessibilityAdjustableAction`. Drawing is not the bottleneck:
expansion, `Tortoise.apply`, and `TortoiseCanvas` all stay near a
millisecond at 1,000 commands (upstream batches committed strokes, and
`ViewportMode` is not a performance lever), so "playback is slow" means a
control redrawing with the playhead. One more platform trap: the centre
button names its grey outright, because `Color.secondary` handed to a
`borderedProminent` tint resolves near-black on macOS.

**The document title appears once.** No column names itself (#23):
`.navigationTitle` and the `.principal` / `.status` placements each collide
with the `DocumentGroup` scene's own title chrome. On iPadOS that chrome
goes to *both* ends of the split view, so a rotation can leave the document
name and its rename chevron on screen twice; `CanvasPane` drops its copy
with `.toolbar(removing: .title)` (#31). The back chevron beside it is not
ours to remove — neither dropping that column's toolbar nor
`navigationBarBackButtonHidden` touches it.

**visionOS needs three things the other two get for free** (#11), and all three
are `#if os(visionOS)` rather than shared, because on iPadOS and macOS each
would be a second copy of something that already exists.

*A way back to the browser.* iPadOS puts a chevron beside the document title
and macOS has File ▸ Open with a window per document; visionOS has neither, so
the window carries the drawing it was opened with and the only route to another
was to close it and launch again. `documentBrowserToolbar()` puts a folder
button in the sidebar's bar, and `dismiss` — what a `DocumentGroup` document
closes itself with — is what it calls. **Where `dismiss` is read from decides
whether it does anything.** Read inside the toolbar item's own view, which is
the obvious place, it resolves against the toolbar's context and the button is
inert: it highlights on press and nothing happens. It has to come from the
environment of the *content* the toolbar is attached to, which is why this is a
`ViewModifier` and not a view inside the `toolbar` block. Nothing warns you —
the code compiles and the button draws.

*The name is deliberately in one place.* The sidebar carries the
DocumentGroup's own title with its rename chevron, and `CanvasPane` still drops
its copy with `.toolbar(removing: .title)` (#31). A second, self-drawn label in
the canvas pane was tried — `\.documentConfiguration`'s `fileURL`, which unlike
the system chrome is right from the first frame — and taken back out: on a
window this wide the two read as one name printed twice rather than as a title
and a reminder.

*A hover effect, but never on a drag source.* visionOS does not give a button
with a custom `ButtonStyle` the system hover treatment, so without
`pointerHover()` a palette block is the one thing on screen that never lights
up when looked at — and gaze feedback is the whole targeting affordance there.
The catch is that a hover effect and `draggable` **on the same view** segfault
(a `swift_release` inside SwiftUI's update of that view's body, before a window
appears). The palette entry is a drag source, so its hover lives inside
`PaletteBlockButtonStyle` — one level below the `Button` that carries
`draggable` — while every other call site applies it directly. The crash blames
the body, not the modifier, which is why this first read as "`hoverEffect`
crashes on visionOS": it does not, the pairing does.

**The code pane is paper, not a semantic surface** (#11). It sat on
`.background.secondary`, which resolves to near-white or near-black on iPad and
Mac but to light translucent glass on visionOS — and the syntax colors had
nowhere to stand: system `.purple` and `.blue` are tuned for an opaque backdrop
and `.plain` was `Color.primary`, which is *white* there, so the plain text and
its ground were both light. It is now white, opaque, the same in both
appearances, rounded the same 8 as the canvas — the two swap places inside one
`ZStack`, so pressing the toggle should change the content and nothing else.
The token colors are fixed values measured against white (8.6:1, 8.4:1, 5.1:1,
16.9:1) for the reason the block fills are fixed (#41). Two traps came with it.
The copy button stays *outside* the paper: on it, it needed the ink as a tint
to be legible, and on visionOS the tint went to the button's capsule instead of
its label, leaving a black lozenge with invisible text. And a program narrower
than the pane sat in the middle of it — in a scroll view that scrolls both ways
the content is offered no width to fill, so a `.leading` frame does nothing and
`defaultScrollAnchor(.topLeading)` is what places it.

**A block row is one VoiceOver element, a container header is not** (#1).
Swiping a program should say "まえへ、かず 100、じっこうちゅう" once per block,
not stop three times, so a simple row is `.accessibilityElement(children:
.combine)`: the kind, its value chips and the running state fuse into one
sentence while the chips keep their own actions, which is what leaves editing a
value reachable. The ⋯ is `accessibilityHidden` and its entries come back as
named actions — as a child it would be both an extra stop and the word
"メニュー" tacked onto every block's sentence. Container headers are deliberately left alone:
combining them would fold in the "Add Here" toggle, and that toggle *is* the
accessible alternative to dragging. Order matters twice here. Accessibility
actions belong *after* the combine, where they attach to the element it built
rather than to a child being merged. And a row's position comes from
`accessibilityCustomContent` (`"Order"` / `"item %lld"`, importance `.high`),
not from the label — the label is assembled by `.combine`, and an explicit one
would replace the whole thing. Note `"Position"` was already taken, by the
scrubber, and means さいせいいち. `DropGap` is `accessibilityHidden` in both
its forms: the invisible one would be an empty stop between every pair of rows,
and an empty mouth's "Drop Here" reads as something to do when it isn't.
Icon-only row buttons wear `touchTarget()`, which is 44pt of hit area on iPadOS
and nothing on macOS, where a pointer never needed it.

**One visible control per row, and it is the menu** (#44). The ⋯ replaced the
always-visible ✕ that #21 had put there, and it holds うえへ / したへ / けす plus
whatever the row adds — the if block's そうでなければ, the else divider's own
"remove". Deleting had three ways in and this was the redundant one; moving a
row had *none* a child would find, because the menu it lived in only opens on
long-press. A visible ⋯ costs けす one tap and buys the reorder commands their
first real affordance: children press what looks pressable, and nobody presses a
block hoping for a hidden menu. Long-press still opens the same menu, so the
macOS right-click keeps working. Note the icon is `ellipsis`, not
`ellipsis.circle` — the row already carries two circled glyphs (the chips and
the ⊕), and a third circle read as another control of the same kind.

**A `Menu` hit-tests its label, so `touchTarget()` goes inside it.** Wrapped
around the outside — where it sat for every `Button` before this — the 44pt
frame grows the layout and leaves the tappable area the size of the glyph. It
looks identical either way, including with the target painted in for a
screenshot, and only shows up as a control that misses half the taps. The ✕ hid
this for as long as it was there, because a filled circle is a large shape on
its own; three dots on a thin band are not. Note the fix is the target and not
the glyph: enlarging the ⋯ was tried alongside it and taken back out once the
44pt label proved enough on device — at `.large` the dots sat heavier than the
words beside them, and a control that is merely easy to hit does not need to be
the loudest thing on the row.

The other half of the same lesson is that a control answers on what it
*draws*. The trash can is a `title2` glyph inside a 56pt frame with a stroked
circle behind it, and it was hit-testing the glyph and the ring only — the
transparent gap between them, most of the target, was not there. `contentShape`
is what puts it back, as a rect rather than a circle so the frame's corners
stay usable and the drop target doesn't shrink with the tap target. Same
symptom as the `Menu` above, different cause, and just as invisible: the
control looks right and misses the taps aimed at the middle of it.

**A row compresses in a fixed order: the spacer, then the label, never a chip.**
Getting there took two modifiers, and neither is the one the symptom suggests.
An if header nested one level deep broke its label onto two lines — 「も」/「し」 —
on iPad, and *widening the column did nothing*, because the row was not short of
width: 60pt of empty space sat beside the label waiting for the menu button. An
`HStack` hands space to its flexible children together, and a wrapping `Text`
and a growing `Spacer` are both flexible, so the label lost to the gap.
`BlockLabelStyle` therefore carries `.layoutPriority(1)`. That alone moves the
damage rather than fixing it: with the label served first, `0.6` in the next row
broke as "0." over "6", which is worse — a chip holds a number, a name or a
colour, all atomic. So `WorkspaceChipButtonStyle` pins its label with
`.fixedSize(horizontal: true, vertical: false)`. Priority rather than
`fixedSize` on the *label*, deliberately: a row deep enough with a long name
genuinely runs out of room, and there the label should still wrap instead of
overflowing its block. Each level of nesting costs 18pt, so no column width wins
that race for ever — the wrap is the correct last resort, not the working state.

**And `ideal` is not a starting point on every platform.** macOS and iPadOS 26
both let the split view's divider be dragged, so there the ideal is only where
the workspace column *opens*. **visionOS has no draggable divider**, so there
the ideal is the width, for good, and the *detail* column absorbs every extra
point the window has. On a 1280pt visionOS window that used to read 360 here
and ~690 on the canvas (#11) — with 「くりかえす 10 かい」 wrapping か/い at the
**top** level, no nesting involved, and 「はこにかける」 splitting in the middle
three levels down. The ideal is now 440, measured against exactly that program:
every row fits on one line at three levels, and the canvas still clears its own
420 ideal. `max` (560) has to stay above `ideal`, or the two platforms that can
drag could only ever drag narrower. Judge a change to it on a *nested Japanese*
program — English fits where 「はこにかける」 does not, and the top-level wrap is
invisible in a flat one.

**Drop model**: a `DropGap` between rows carries `(BodyAddress, index)`, so
insertion semantics need no y-coordinate math and every mouth — an if's else
included — is a target. The targeted one **parts to a block's height** (#77) —
it holds the space the block is about to fill, rather than drawing a line
where it will go. There is no line in it: a 4pt capsule floating in 44pt of
opened space read as two answers to one question. Tap-to-add, with the "Add
Here" toggle (`InsertionTargetButton`) on container headers and the else
divider, is the accessibility alternative and must stay. A permanent trash
circle rides a `safeAreaInset` at the bottom of the workspace
(`WorkspaceTrashZone`, #30) — the way out of a drag you regret, since deleting
a *placed* block was never the hidden part.

**The gaps tile, and that is what makes the parting bearable.** A closed gap
reports the row-to-row margin to its `VStack` and is hit-tested over a whole
row's *pitch*, the two held apart by negative padding (the #21 trick, widened).
At the 24pt it used to be, most of every row was ground no gap claimed: dragging
down the program closed every gap and opened another at each boundary, and the
list pulsed the whole way. **Something has to be open at all times, and the way
to get that is to leave nowhere that isn't a gap.** The oscillation this
invites — the open gap moving out from under the finger — does not happen,
because the gap that opens is the one being pointed at and it grows around that
point. All of this was judged on an iPad, which is the only place it can be:
the question is what happens under a finger.

**The Mac badges those gaps anyway, and cannot be talked out of it** (#101).
The system puts a ⊕ on the preview over any drop destination without asking
whether the drop would achieve anything. On iPadOS, taking the gap out of hit
testing takes the badge with it. On macOS nothing does: `allowsHitTesting`,
`.disabled(_:)`, and `dropConfiguration` returning
`DropConfiguration(operation: .forbidden)` were each built and watched, and the
badge stayed through all three. Do not try them again in that order. The Mac
shows a ⊕ over a gap that will refuse the block; the refusal has always been
correct, and the space still stays shut, so what is left is one wrong glyph.

**And the replacement drop API cannot be adopted yet** (#99). Ours —
`dropDestination(for:action:isTargeted:)` — is soft-deprecated in favour of
`dropDestination(for:isEnabled:action:)`, whose `isEnabled` is exactly the
lever the badge wants. It has no `isTargeted`, and the session observers that
would replace it (`onDropSessionUpdated`, `dropConfiguration`) are
`@available(iOS, unavailable)`. Migrating would trade a cosmetic Mac defect for
a broken parting on the platform this app is for. The deprecation is silent —
`deprecated: 100000.0`, so no build warning — which is why it went unnoticed
for so long; it is not urgent, and it is not actionable until a targeting
signal exists on iOS.

**A gap that cannot take the block stays shut** (#98). Opened space is a
promise that something will land there, and two gaps make it falsely: the ones
either side of the block being dragged, where a drop puts it back where it was,
and any inside the dragged block's own subtree, which the tree refuses outright
— the destination vanishes with the extraction. They stay drop destinations
regardless, because taking them out of the tiling would bring the pulsing
straight back; they simply do not open, and the drop is refused as it always
was.

Which gaps those are is answered by `BlockTree.dropChangesTree`, which
**performs the move and compares** rather than restating as rules which drops
are pointless — one set of rules cannot drift from another if there is only
one. And what the drag is carrying comes from `draggable`'s payload, an
`@autoclosure` evaluated once per drag, recorded into `WorkspaceUIState` on its
way past. **There is no "a drag started" signal on iOS**, `onDragSessionUpdated`
being macOS-only — the same hole that made the trash can permanent (#30), met a
second time. There is no "a drag ended" either, and here that costs nothing:
the value means something only while a drag is in flight, a gap only reads it
while something hovers over it, and the next drag overwrites whatever a
cancelled one left behind.

**The can does two things, and the second one made it accessible** (#48). A drop
throws away the block you are holding; a *tap* offers to throw away the program,
which is what #44 took away when the row's ✕ became a menu — clearing a
workspace by opening one menu per row is not a thing a child will do. The two
never collide, being different gestures, and the tap asks first. Being a
`Button` is also what let the can stop being `accessibilityHidden`: a drop
target is nothing a VoiceOver user can operate, so it had been invisible since
#30, and it can now say what it is. The confirmation is an **alert**, not a
`confirmationDialog`: on iPad the latter is a popover hanging off the can, and
that form drops the title *and* the cancel button — the question never gets
asked, and the way out is the one control not on screen. It is one alert for
both entry points (the can and the Mac's ⌘⌫), living on `WorkspaceView` and
driven by `WorkspaceUIState.confirmsDeleteAll`, because two presentation
modifiers of the same kind would silently swallow one another. It can't appear only mid-drag: SwiftUI has no
cross-platform "a drag started" signal (`onDragSessionUpdated` is
macOS-only), so a can that appeared on drag could never reliably learn the
drag was cancelled. It replaced drop-on-the-palette deletion, which had no
way to announce itself (`dropDestination`'s `isTargeted` gives only a `Bool`,
so the palette couldn't highlight for workspace drags alone). Dropping a
palette-origin block on it is a no-op — `BlockTree.removing` returns nil for
an ID that isn't in the tree, which is exactly right.

**Compact width is not a design target** (#29). There is one layout,
`RootView`'s three-column `NavigationSplitView`; the "つくる / うごかす" tab
pair and its bottom palette strip are gone, because three panes' worth of
information never folded into one 390pt column usably. An iPad window narrow
enough to report compact (Slide Over, a squeezed window) gets
`NavigationSplitView`'s own collapse — that is the whole fallback, and no
`horizontalSizeClass` branch should come back. Don't restore a compact
layout without reopening the scope decision.

**Row icons share one slot width.** SF Symbols differ in width by up to 9pt
at body size, and `Label` lets each title start wherever its own icon ended,
so a column of rows comes out ragged. `BlockLabelStyle` centres every icon in
a slot sized by a hidden copy of `widestSystemImage` (`house`) — measured, not
hard-coded, so it stays right across the macOS body size (13pt), the iOS one
(17pt), and every Dynamic Type step. A *wider* symbol isn't clipped; it pushes
its own title right and the ragged edge is back, so a new block kind's icon
has to be no wider than `house` (or that constant moves to the new widest).
This is not theoretical: #14's obvious pick, `puzzlepiece`, measures 22pt
against `house`'s 19 at 13pt and would have done exactly that — the blocks use
`puzzlepiece.extension` / `.extension.fill`, which are joint-widest with
`house` at every size and never over. Measure rather than eyeball; a few lines
of AppKit (`NSImage(systemSymbolName:)` + `.withSymbolConfiguration`) settles
it in seconds.
The style is on the palette entries and every workspace block row, but not on
`PaletteEntryChip`, whose icon sits above a centered title.

**And one height.** Row height otherwise follows the tallest control the row
happens to hold — 32pt for a bare label, 40pt with a value chip, 43pt for a
container header (macOS body size) — so a program steps unevenly down the
page. `rowShape()` is the shared outer shape: a hidden `RowHeightFloor`
stacked behind the content, then the row padding. `BlockChrome` wears it, and
so does an empty mouth's "drop here" zone, which stands in for a row and so
has to measure like one (its 2pt outer margin sits outside the shape, playing
the same part as the gap between rows). The floor is measured rather than
hard-coded, and correct only while nothing taller joins a row. Note the
failure mode is silent in both cases: too small a floor leaves the tall rows
tall, exactly as if the fix were missing.

**The sixth category is coral, and a definition wears a hat** (#14). The hues
were 200° sky / 270° wisteria / 140° mint / 33° apricot / 340° blush, leaving
gaps at yellow (~55°) and teal (~180°) with red squeezed between the last two.
Judged in a prototype against the other five, yellow sat too close to apricot —
and a definition wrapping an if puts those two side by side by construction —
while teal read as a shade of the sky blocks; coral is the narrow gap and holds
because its *saturation* differs from blush as well as its hue. It is `#F8B4A8`
rather than the prototyped `#F5A79B` so ink clears the same ~9.8:1 as the other
five (that one measured 8.8): a fill's lightness is what carries the label, and
one darker block reads as the odd one out long before anyone measures it.
`RowCorners.definitionHeader` then rounds the top corners to 20 against a
container header's 10. That hat is the only thing saying a block is *not part
of the sequence it sits in* — the program is one column, so a definition
dropped into it otherwise reads as something that happens at that point, which
is precisely what a definition doesn't do. Scratch can say this by putting
definitions elsewhere on a 2-D canvas; a column has only the silhouette. The
alternative — rendering definitions in a section of their own below the program,
which the execution's hoisting would have justified — was prototyped and turned
down: the highlight jumping out of the program into a separate list during
playback is worse than a shape you learn once.

**Blocks are opaque pastels under fixed dark ink** (#41), drawn from the app's
own artwork — the icon's sky-to-mint gradient, the mascot's lavender, apricot
and blush — rather than from the system palette. They started as saturated
system colors under white text, which measured 1.9–3.3:1 against white: under
AA for every category, in both appearances, and the running-block highlight
made it worse. Keeping white would have meant darkening the fills until orange
came out brown (`#A76821` at 4.5:1, still `#D2832A` even at 3:1) — green and
orange are intrinsically light hues, so a white-text rule drags them somewhere
they can no longer be named. Ink on pastel clears 9.8:1 on all five instead,
and no hue moves. This is *not* the pale tint #21 rejected: that was
`opacity 0.15` over the pane, a see-through wash; these are opaque, and
"blockiness" turns out to come from opacity and a defined edge rather than
from saturation.

Three rules follow from the fills being light in *both* appearances. The label
color must **not** follow the appearance — `Color.primary` would invert and put
white back on a pastel, at 1.4:1 — so `BlockCategory.ink` is a fixed
`#1C1C1E`. The highlight ring must, because its job is to stand out against
both the pastel inside it and the pane outside, and which of black or white
does that is exactly what the appearance decides. And the white value chip
needs a drawn outline: at 1.5:1 against a pastel it no longer reads as a
control on its own, so `WorkspaceChipButtonStyle` strokes it at ink 0.55 —
measured, since 0.35 came out around 2:1 and 0.52 is where the worst fill
crosses WCAG's 3:1 floor for a control boundary.

**The accent is the mascot's purple** (`#B64AE5`) — the sprite's own violet,
held a little deeper. Its hat, shell and the tail that *is* the pen average
`#C650F9`, which carries the run button's white glyph at 3.55:1: over the 3:1
floor for non-text but without much room, so the accent takes that hue a shade
darker and gets 4.12:1. It shares a hue with the pen category's lavender on
purpose: the pale purple is the pen blocks, the strong purple is the brush and
the run button, and "purple means drawing" reads as one idea. It replaced a
teal picked when the categories were saturated and purple would genuinely have
collided; that teal also carried the same glyph at only 2.16:1. **Re-sample the
sprite when the artwork changes** — this pairing is the one place a redrawn
mascot silently stops matching the app (it already happened once: the first
version of this accent came from the previous sprite's `#A659E6`). Stored as a literal
rather than a system reference, so it is the same in both appearances — like
the fills, it is the app's identity and not a response to its surroundings.

**A container is one C-shaped block, assembled from parts.** Indent plus a
3pt guide bar left "what is inside this repeat, and where does it end?"
to be inferred; `ContainerBlockRow` now draws the Scratch/Blockly C — header
along the top, a 12pt spine down the left, an 11pt foot along the bottom,
all in the category color, with the children held off the spine by a 6pt
gutter (so a level of nesting costs 18pt, up from 16pt). The arms are
*drawn additively, not cut out of one shape*: nothing has to know the
mouth's geometry, and — the reason this beat filling the mouth with a
matched color — nothing has to guess the pane's background, since the
mouth is simply where no arm is drawn. `RowCorners` holds the whole shape
vocabulary: a standalone row rounds 8 everywhere; the C's four outer
corners round 10 and the two facing the mouth round 8; every edge the
spine runs on through (a header's bottom-leading, both leading corners of
the else divider) stays square, and that squareness is what makes the
pieces read as one block. Verify it that way too — a vertical scan down
the spine of a rendered container must be one unbroken run of the
category color, through the else divider and into the foot.

**Motion is added at the edit, and switched off in one of two places** (#70,
#71). Every tree edit — add, delete, reorder, drop, undo, redo — comes through
`WorkspaceEditor.apply`, so that one function bumps
`WorkspaceUIState.editGeneration` and the block list animates on the counter.
Not on `[Block]`: this view re-renders on every committed command during
playback, and comparing two whole trees ten times a second is the wrong price
for "did an edit happen?" — the same reason the staleness hash sits in
`CanvasPane`. Keep the `.animation(_:value:)` innermost, too. The same edit
also changes the toolbar's undo/redo enablement and the transport's staleness,
and neither should move because a block did.

Reduce Motion then takes one of two shapes, and which one is decided by
whether the motion is declarative. Declarative motion hides the check in a
modifier, the way `pointerHover()` hides `#if os(...)`: `blockEditAnimation`
passes `nil` instead of a spring. An imperative `withAnimation` has no modifier
to hide inside, so `WorkspaceView` reads `accessibilityReduceMotion` itself and
hands `withAnimation` the same `nil` — that is the *only* reason to read the
environment value in a body. Note that reduced motion still **moves**: a scroll
that brings a new block into view has to arrive either way, it just arrives
without the travel. There is no third shape, and forgetting both fails
silently — motion nobody switched off simply plays.

**And a `Group` cannot carry that animation** (#72). `Group` hands its
modifiers to each *child*, so `.animation(_:value:)` on
`Group { if A { X } else { Y } }` lands on whichever branch is showing; when
the branch flips, the new child gets a fresh modifier with no previous value to
compare against, and the one change you wanted animated is the one that cannot
be. `safeAreaInset` is distributed the same way, which is why the trash can cut
along with the pane. The workspace's two states therefore sit in a `ZStack`:
a real container is a stable ancestor, and it holds both states in the same
space, which is what a cross-fade is. `CanvasPane`'s canvas/code swap was
already a `ZStack` and already worked — same modifier, same kind of value,
different container — which is how the two were told apart. Nothing warns you:
the modifier is written, the build is clean, and the pane simply cuts.

**A drag preview is proposed the source view's size, so it fills rather than
measures** (#87, #91). `draggable(_:preview:)` hands the preview the size of
the view it was attached to, which means `.frame(maxWidth: .infinity)` gives a
preview exactly the width of the row or palette entry it came from — no
measurement, no plumbing. Without it a preview shrinks to its own content,
which reads as a smaller block than the one that was under the finger.

This was found the hard way and the wrong way round. The first attempt measured
each source with `onGeometryChange` and handed the number to `.frame(maxWidth:)`
— which is a *ceiling*, not a width, so a value wider than the content
collapsed straight back to the content and the whole mechanism looked like it
worked while doing nothing. Using the same number as a fixed `.frame(width:)`
on the container exposed the second half: **`onGeometryChange` does not report
the rendered width here.** Measured against a 100pt rectangle drawn on screen,
a row draws 408pt — the column's 440 less the list's 32 — while the modifier
reports 359, and the `ScrollView` above it reports 391 for a 440pt column. The
error starts at the top and every level inherits it intact (359 = 391 − 32).
Why is unknown; what matters is that geometry read inside this column is not
the geometry on screen, so do not build on it. The container preview is what
gave the answer away: it filled correctly all along, because `DropGap` carries
a `maxWidth: .infinity` and was quietly doing what every preview should.

**And an iPad has no Taptic Engine** (#74). `UIImpactFeedbackGenerator` — what
`.sensoryFeedback`'s `.impact`, `.success` and `.error` are built on — is
iPhone-only; the iPad's only haptics come from an Apple Pencil Pro or an M4
Magic Keyboard trackpad, through a different generator, and never from a
finger. This app ships to iPad, Mac and Vision Pro and no iPhone
(`TARGETED_DEVICE_FAMILY` is "2,7"), so `.sensoryFeedback` is inert on every
device it runs on. It fails silently — no error, no warning, nothing happens —
which is exactly how a full implementation of it got written and then thrown
away. Sound (#80) is the only channel left for answering a touch.

**iPadOS fills whatever a drag preview leaves transparent** (#93), and none of
what follows is visible on a Mac — every one of these was found the first day a
device could show a drag preview at all (#90 blocked that until an OS update).

A block came up with white in its rounded corners, because the system
composites a preview onto an opaque backing and paints the parts the snapshot
does not cover. `contentShape(.dragPreview,)` names the block's own outline and
the corners come back. It belongs on the *preview content*, not in
`BlockChrome`: the real rows wear that modifier too, and a shape declared there
reaches the whole preview — which on a container is the header's rectangle, and
clips the spine and the foot clean off the C.

**A container cannot hand it a shape at all.** The C is drawn additively from
three pieces, on purpose (nothing has to know the mouth's geometry), and that
is exactly what leaves no single outline to declare: covering the arms while
skipping the mouth needs the header's height, which no `Shape` can read. So a
dragged container goes on a card instead, in `.background` so it holds up in
both appearances — and with **the header's own corner radii rather than a
number**. Written as a flat 10 it left a crescent of card showing around a
definition's 20pt hat (#14): the same white corner the card was put there to
remove, back on the one block with a different silhouette. `RowCorners` is the
vocabulary; take the radii from it rather than writing one out.

Two things follow, both judged on device and accepted. The card shows through
the gap between the last child and the foot, where the pane would show in the
workspace. And the height cap's fade now dissolves into the card rather than
into nothing, because the system paints the named shape opaque: "more below"
still reads, it just reads on a card. The alternative — leaving the four outer
corners white — was built, looked at, and judged worse.

**A drag preview's width takes two modifiers, one per platform** (#91, #95).
macOS proposes the source view's size to the preview, so `maxWidth: .infinity`
is enough there. iPadOS proposes nothing, and a greedy frame with no proposal
falls back to the content — which is how every preview came out narrower than
the block it was lifted from. The floor has to be measured and handed over, so
each source reports its width through `onGeometryChange` and its preview wears
`.frame(minWidth: measured, maxWidth: .infinity)`. Neither half covers both
platforms, and on macOS the measured value is ignored, which is just as well:
**`onGeometryChange` does not report the rendered geometry inside this column**
— see below — while on iPad it happens to be right.

**Measure with a `GeometryReader`, not with `onGeometryChange`** (#102). The
modifier is the one SwiftUI offers for this and the one the house rules prefer,
and inside the workspace column it returns numbers that are not on screen. Both
were put on the same view at once and read off a Mac: the modifier said a
container header was **159pt** tall where the reader said **44** and a ruler
drawn on screen confirmed ~45. It under-reports width in the same place (#95):
**359** against a row that draws **408**, and **391** for a 440pt `ScrollView`.
Why is unknown. The reader is right on both platforms; `measuringHeight(into:)`
wraps the pattern.

Two things were built on the wrong number before this was found, and both are
worth knowing as symptoms. A container's drag preview was capped by "header
plus a glimpse" and showed a whole extra block on macOS against a third of one
on iPad — the same constant, a header measured 159 on one platform and ~52 on
the other. And the width floor in #95 rests on a value macOS ignores, which is
the only reason it works there. **When a measured layout number explains
nothing, suspect the measurement before the layout** — and settle it with a
rectangle of known size drawn on screen, which costs one build
(`open -a TortoiseBlocks <file>.tortoise` puts a document up to measure).

What the lift gets right, the drag then changes: **iPadOS scales the preview
down once it is moving.** Nothing in `draggable` influences that, and UIKit's
own preview API governs shape and background rather than size in flight. The
size we control is the one at the moment of the lift, and it matches.
