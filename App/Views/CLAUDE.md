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
`fixedSize` on the *label*, deliberately: a row two levels deep with a long name
(「はこにかける」) genuinely runs out of room, and there the label should still
wrap instead of overflowing its block. Each level of nesting costs 18pt, so no
column width wins that race — the wrap is accepted there.

**Drop model**: a `DropGap` between rows carries `(BodyAddress, index)`, so
insertion semantics need no y-coordinate math and every mouth — an if's else
included — is a target. Tap-to-add, with the "Add Here" toggle
(`InsertionTargetButton`) on container headers and the else divider, is the
accessibility alternative and must stay. A permanent trash circle rides a
`safeAreaInset` at the bottom of the workspace (`WorkspaceTrashZone`, #30) —
the way out of a drag you regret, since deleting a *placed* block was never
the hidden part. It can't appear only mid-drag: SwiftUI has no
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
