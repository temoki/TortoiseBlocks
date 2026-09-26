# The teaser video

The website's video — a program built by trial and error, from one line to a
spiral of stars — is made here, not filmed by hand.

```bash
ruby Tools/teaser/teaser.rb             # record on the iPad simulator, then compose
ruby Tools/teaser/teaser.rb --compose   # compose the last recording again
```

The film comes out silent, 1920×1080 at 30fps, about two minutes, in the
work directory the script prints (`$TMPDIR/tortoise-teaser/teaser.mp4`), with
the raw recording beside it. Music is added afterwards, by hand.

Three pieces:

- **`TortoiseBlocksUITests/TeaserTests.swift` is the script.** Every press,
  when each caption comes up, and where the camera looks, in the order they
  happen. Changing the story is editing this file. The test writes a log of
  what it did and when (`events.jsonl`); it does not decide anything about the
  film.
- **`teaser.rb` is the crew and the editor.** It records the simulator while
  the test runs, then cuts, frames, zooms, captions and draws the touches from
  the log.
- **`text.swift`** renders captions and titles in SF Pro Rounded, because
  ImageMagick cannot ask the system's variable font for a weight.

It needs Xcode, `ffmpeg` and ImageMagick (`magick`). A full run takes about a
quarter of an hour, nearly all of it the recording; composing again takes two
minutes. Don't run it while a screenshot rig is
running: they share DerivedData (see the `screenshots` skill).

## Things that look like mistakes and are not

**The shoot is on the 11-inch iPad**, not the 13-inch one the App Store
captures use. It has the same layout in fewer points, so every block is about
a quarter larger in a 1080p frame. At 13 inches the palette's text came out a
few pixels tall.

**Most of the recording is thrown away.** A UI test is slow: every press
waits for the app to go idle, finding an element takes a snapshot, and a
typed digit takes seconds. The raw run is almost four minutes. The simulator
writes a frame only when the screen changes, so the gaps between frames are
exactly the still stretches. Each one is cut down to `HEAD` seconds, except
where the log asks for time: a caption to read, a camera move to finish, the
moment around a touch, and `linger` (a finished drawing, the code at the end).
The test's own `pause`s therefore don't set the pace. They only give the app
time to settle. Two refinements: while a number is being typed the field's
caret blinks, and every blink is a frame, so the test logs the typing span and
only the keys inside it are kept. And a drawing longer than `LONG_DRAWING`
plays at `FAST`×: the spiral takes nine seconds at the app's own tempo.

**A drop that did not land is cut out.** A drag in the simulator now and then
parts the rows and inserts nothing. The test checks that the block arrived,
tries again if not, and logs the failed take as a `cut`, which the film leaves
out.

**Touches are drawn afterwards.** The simulator's recording shows no finger,
and the log already knows where each press went. A tap is logged just after it
returns, and the screen reacts 0.1–0.26s before that (measured against the
first changed frame), so the finger is drawn landing `TAP_LEAD` earlier. A drag
is worked back from when it returned: its hold, its travel at the velocity it
was given, and its linger.

**The camera is part of the log, not the edit.** `camera(.blocks)` in the test
records a rectangle in screen points. The film eases to it, zooming so that
the rectangle fills the frame. The zoom is `zoompan` on the full-resolution
source, so the text stays sharp at 2×.

**Presses are coordinates, so nothing scrolls for them.** `XCUIElement.tap()`
scrolls its element into view first; a coordinate tap below the fold presses
whatever is there. On the 11-inch iPad that includes Repeat, and the first run
put a Start Fill where the repeat should have been. `palette(_:)` scrolls the
palette with a finger until the entry is on screen. Coordinates are used anyway
because the log needs the point that was pressed.

**The palette entry is the leftmost button with that label.** "Forward" is
also the transport's step button. It is a separate element with the same name,
and a query that walks its matches one by one lost one between counting and
fetching.

**A hardware keyboard is attached for the run**, by switching the Simulator's
`ConnectHardwareKeyboard` preference on and restarting the device to pick it
up. Xcode 27 has no Simulator.app to attach one by hand. The
preferences are exported first and imported back when the run ends. Without
it, a number field raises the full on-screen keyboard over half the screen. The maintainer's own recording
used a pointer and a keyboard, so none shows there either. The value is typed
after a tap in the middle of the field, which puts the caret at the end, so
the old digits go by backspace. `⌘A` is not used: selecting brought iPadOS
27's small number keypad up over the field, and sometimes the full keyboard
under it.

**"Drawing finished" means the scrubber settled after it moved or had time
to.** It does not require a new end value: changing an angle leaves the step
count alone, so the run ends on exactly the value the previous one did, and
waiting for a different value waited forever. It does not require seeing the
scrubber move either: a press returns only once the app is idle, which once
took nine seconds, and an eight-step triangle is drawn in 0.8.

**The recording is sideways and variable-rate.** `simctl io recordVideo`
writes the framebuffer as it is held (portrait, the landscape app on its side)
and only when something changes. `transpose=2` stands it up, and `fps=30`
fills the still stretches before anything is cut.

**The system language is English for the run** as well as the app, because
the status bar writes its date in the system's language. It is put back
afterwards, as `ipad-shots.rb` does.
