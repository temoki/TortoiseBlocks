# The films

Two kinds of video are made here, from scripts, rather than filmed by hand:
the website's teaser, and the App Store's previews.

```bash
ruby Tools/film/teaser.rb                # the teaser: record on the iPad simulator, then compose
ruby Tools/film/teaser.rb --compose      # compose the last recording again

ruby Tools/film/previews.rb              # every preview: iphone, ipad, mac, vision
ruby Tools/film/previews.rb ipad mac     # only the ones named
ruby Tools/film/previews.rb --compose    # compose the last recordings again
```

Everything comes out silent, English and ready for music, which is added by
hand. The films land in a work directory the scripts print
(`$TMPDIR/tortoise-teaser/`, `$TMPDIR/tortoise-previews/`), next to the raw
recordings. None of it is committed: each film is megabytes, and fastlane's
deliver uploads screenshots but not previews, so App Store Connect takes the
previews by hand.

The pieces:

- **The scripts are UI tests.** `TeaserTests` and `AppPreviewTests` (iPhone,
  iPad), both on `FilmTestCase`, and `MacPreviewTests` on its own. Each one
  lists every press, when each caption comes up, and where the camera looks,
  in the order they happen. Changing the story means editing the test. A
  script writes a log of what it did and when (`events.jsonl`); it decides
  nothing about the film.
- **`film.rb` is the crew.** It records a simulator while a test runs, cuts the
  recording down to what moves, and draws the touches.
- **`teaser.rb` and `previews.rb` are the editors.** The teaser gets a
  backdrop, a camera, captions and cards. The previews get only what Apple
  allows (see below).
- **`text.swift`** renders the teaser's captions and titles in SF Pro Rounded.
  ImageMagick cannot ask the system's variable font for a weight.
- **`window-recorder.swift`** records the Mac's window with ScreenCaptureKit.

It needs Xcode, `ffmpeg` and ImageMagick (`magick`). The teaser takes about a
quarter of an hour, nearly all of it recording. The previews take about five
minutes each. Don't run either while a screenshot rig is running: they share
DerivedData (see the `screenshots` skill).

## The previews

Apple's rules are what shape these, and they are stricter than the teaser's
(developer.apple.com/app-store/app-previews/, and the preview specifications
in App Store Connect's help):

- **The screen as captured.** No zooming into the UI, so there is no camera.
  Nothing that is not the device either: no backdrop, no cards. The Mac's
  desktop is the exception, and it is the same drawn plate the screenshots
  stand on. Graphics that show where to touch are allowed, so the touches are
  drawn as in the teaser. By the maintainer's choice, there are no captions.
- **15 to 30 seconds.** A cut that comes out short holds its last frame. One
  that comes out long stops the run.
- **One exact size per device class**, 30fps at most, H.264 High, and an audio
  track, which is required even when it is silence. iPhone is 886×1920, iPad
  1600×1200, Mac 1920×1080 and Vision Pro 3840×2160.

Fifteen seconds is too short to build a program from nothing and still watch
it draw. So each script starts from a document that already holds most of
one, written in `PREVIEWS` in `previews.rb`.

**The iPad is shot on the 13-inch, not the teaser's 11-inch.** A preview is
4:3, which only the 13-inch is. The 11-inch would have to be cropped, and a
preview may not be.

**Vision Pro's is H.264 Level 5.1, not the 4.0 the specification names.**
Level 4.0 stops at 8,192 macroblocks, and 3840×2160 is 32,400. Whether App
Store Connect accepts it is checked at upload.

**On a phone, the number pad is pressed; on an iPad, the value is typed.** A
phone's pad is what a phone is used with, so the touches drawn over its keys
are the real ones. A phone showed its pad under the hardware-keyboard
preference in one run and not in the next, so `setNumber` looks for the pad
rather than assuming either. Keys pressed one after another leave no
stillness to find the touch by, so a key's touch is taken as `KEY_LAG`
(0.26s, measured) before the tap returned.

**Vision Pro is launched, not scripted: a simulator takes no input.** The
preview is the viewer doing what it is for, the star drawn on the table. The
launch arguments are the screenshot rig's, plus `-TBPlay 6`. **Recording
starts after the sheet is up, never before the launch.** With `simctl io
recordVideo` running while the app launches, the immersive space does not open
at all. The windows come up and the app reports `TBNotReady`, every time,
whether or not the simulator was restarted. So the app waits six seconds
before it plays: the sheet comes up, the recorder starts, and the drawing
begins at `TBPlaying`, whose log timestamp is where the cut starts.

**The Mac is recorded on this Mac**, by ScreenCaptureKit, while
`MacPreviewTests` drives the real pointer. It wants the machine left alone for
a few minutes with the screen unlocked, and **macOS asks for the password**
before it lets a UI test take the pointer. That is the automation mode
`automationmodetool` reports. Nothing is drawn over the Mac's film: the
recorder keeps the pointer and its clicks. Four things stood in the way:

- *The test runner is sandboxed.* It cannot write where the driver can read,
  and the driver cannot write into its container. So the log comes back as
  an attachment in the result bundle. The recorder watches for the window to
  appear instead of waiting for a signal, and the test gives it an
  eight-second head start once the document is open.
- *A window recorded as itself wears macOS's purple "sharing this window"
  control* where its close, minimise and zoom buttons belong, in every frame.
  It also answers to the window's title, which made the test's window query
  ambiguous. So the recorder takes the display with every other application
  removed, the wallpaper included, and crops it to the window. Outside the
  window's corners is then black, and one frame's corners are flood-filled to
  make the mask.
- *That recording writes frames whether or not anything changed*, so stillness
  is judged by content: a frame counts as a change only if `mpdecimate`
  keeps it (`Cut.new(raw, by_content: true)`).
- *A row's chips fold into the row on a Mac.* On iOS "Number 90" is a button
  inside "Turn Right, Number 90". On a Mac the row is the one element, so the
  chip is placed by measurement: 41pt of padding and icon, then the label in
  the system font. A screenshot of the row was tried first and found nothing,
  because the runner's screenshots do not show the app's window.

## Things that look like mistakes and are not

**The teaser is shot on the 11-inch iPad**, not the 13-inch the App Store
captures use. It has the same layout in fewer points, so every block is about
a quarter larger in a 1080p frame. At 13 inches the palette's text came out a
few pixels tall.

**Most of every recording is thrown away.** A UI test is slow: every press
waits for the app to go idle, finding an element takes a snapshot, and a
typed digit takes seconds. The teaser's raw run is almost four minutes. The
simulator writes a frame only when the screen changes, so the gaps between
frames are exactly the still stretches. Each one is cut down to `HEAD`
seconds, except where the log asks for time: a caption to read, a camera move
to finish, the moment around a touch, and `linger` (a finished drawing, the
code at the end). The tests' own `pause`s therefore don't set the pace. They
only give the app time to settle. Two refinements. While a number is being
typed, the field's caret blinks, and every blink is a frame, so the test logs
the typing span and only the keys inside it are kept. And a drawing longer
than `LONG_DRAWING` plays at `FAST`×, because the spiral takes nine seconds at
the app's own tempo.

**The recording is converted with `-fflags +igndts`.** The recorder writes
decode times that drift away from the presentation times, by eleven seconds
by the end of one phone recording. Without the flag the conversion followed
the wrong clock, and the film cut to the home screen before the drawing had
finished.

**A touch is found in the recording, not read off the log.** A tap is logged
when it returns, and that is after the app has gone idle again: 0.1–0.3s after
the touch on an iPad, up to 1.4s on a phone, where a sheet has to finish
moving first. XCUITest touches only once the app is idle, so the touch is the
first frame after the tap was called (`t0`) that breaks a stillness of
`QUIET`. It is not the burst of frames the tap returned in: a settled sheet can
still draw one late frame, and that frame is not the touch.

**A drop that did not land is cut out.** A drag in the simulator now and then
parts the rows and inserts nothing. The test checks that the block arrived,
tries again if not, and logs the failed take as a `cut`, which the film leaves
out.

**The teaser's camera is part of the log, not the edit.** `camera(.blocks)` in
the test records a rectangle in screen points. The film eases to it, zooming so
that the rectangle fills the frame. The zoom is `zoompan` on the
full-resolution source, so the text stays sharp at 2×.

**Presses are coordinates, so nothing scrolls for them.**
`XCUIElement.tap()` scrolls its element into view first. A coordinate tap
below the fold presses whatever is there. On the 11-inch iPad that includes
Repeat, and the first run put a Start Fill where the repeat should have been.
`palette(_:)` scrolls the palette with a finger until the entry is on screen.
Coordinates are used anyway because the log needs the point that was pressed.

**The palette entry is the leftmost button with that label.** "Forward" is
also the transport's step button. It is a separate element with the same name,
and a query that walks its matches one by one lost one between counting and
fetching.

**A hardware keyboard is attached for the run.** The scripts switch the
Simulator's `ConnectHardwareKeyboard` preference on and restart the device to
pick it up. Xcode 27 has no Simulator.app to attach one by hand. The
preferences are exported first and imported back when the run ends. Without
it, an iPad's number field raises the full on-screen keyboard over half the
screen. The maintainer's own recording used a pointer and a keyboard, so none
shows there either. The value is typed after a tap in the middle of the field,
which puts the caret at the end, so the old digits go by backspace. `⌘A` is
not used: selecting brought iPadOS 27's small number keypad up over the field,
and sometimes the full keyboard under it.

**"Drawing finished" means the scrubber settled after it moved or had time
to.** It does not require a new end value: changing an angle leaves the step
count alone, so the run ends on exactly the value the previous one did, and
waiting for a different value waited forever. It does not require seeing the
scrubber move either. A press returns only once the app is idle, which once
took nine seconds, and an eight-step triangle is drawn in 0.8. On a phone
there is no scrubber at all until the run is under way.

**The recording is sideways and variable-rate.** `simctl io recordVideo`
writes the framebuffer as it is held (portrait, with a landscape app on its
side) and only when something changes. `transpose=2` stands it up, and `fps=30`
fills the still stretches before anything is cut.

**The system language is English for the run**, as well as the app's, because
the status bar writes its date in the system's language. It is put back
afterwards, as `ipad-shots.rb` does.
