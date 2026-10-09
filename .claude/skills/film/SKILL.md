---
name: film
description: >-
  Making the videos: the website's teaser (Tools/film/teaser.rb) and the App
  Store app previews for iPhone, iPad, Mac and Vision Pro
  (Tools/film/previews.rb) — recording UI tests on the simulators and on this
  Mac, cutting them to Apple's rules, checking the result, and leaving the
  previews in appstore/previews/ for upload. Load this before reshooting either, before
  changing what a film shows, and whenever a film run fails or a film looks
  wrong. Still pictures are the `screenshots` skill.
---

# Films

Two kinds, one set of tools in `Tools/film/`. The scripts are UI tests. The
Ruby records them, cuts out the waiting, and edits. **`Tools/film/README.md` is
the why** — every rule, number and trap is explained there, so read it before
changing anything. This file is the how.

```bash
ruby Tools/film/teaser.rb               # the website's teaser, ~15 min
ruby Tools/film/previews.rb             # iphone ipad mac vision, ~5 min each
ruby Tools/film/previews.rb ipad mac    # only the ones named
ruby Tools/film/previews.rb --compose   # re-cut the last recordings, no shooting
```

Every film comes out English, silent and uncommitted, in `$TMPDIR/tortoise-teaser/`
or `$TMPDIR/tortoise-previews/`. The previews are also copied to
`appstore/previews/<name>.mp4` (gitignored), which is where
`ruby Tools/appstore.rb push` sends them from — silent, as they are. Music is
added by hand only to copies made for elsewhere, such as YouTube. **Make the
previews only when the maintainer asks**: a push sends whatever is in
`appstore/previews/` and never reshoots, and a missing video is reported, not
made.

## Before a run

- **One rig at a time.** The films share DerivedData with the screenshot rigs;
  check `pgrep -f 'shots.rb|film/'` first.
- **Tell the maintainer before the Mac preview, and wait for them.** It drives
  this Mac's real pointer for three or four minutes, the screen has to stay
  unlocked, and macOS asks for the password before a UI test may take the
  pointer (`automationmodetool` says "requires user authentication"). The
  maintainer chose to type it each time rather than switch the check off, so
  say when the dialog is coming, and say again when the Mac is free. The
  simulator films need nothing from them.
- A run changes the Simulator's `ConnectHardwareKeyboard` and the simulators'
  language, and puts both back when it ends. After an interrupted run, check
  `defaults read com.apple.iphonesimulator ConnectHardwareKeyboard` is back to
  what it was (0 here).

## Changing what a film shows

- **The story is the test.** `TeaserTests`, `AppPreviewTests` (iPhone, iPad)
  and `MacPreviewTests`. Pauses only give the app time to settle. The pace is
  set by the cut, and `linger(_:)` is how a script asks for a moment to be held.
- **A preview starts from a document that is already nearly a program**,
  written in `PREVIEWS` in `previews.rb`. Keep a preview to 15–30s: a short
  cut holds its last frame, and a long one stops the run. Vision Pro has no
  script, only launch arguments (sample, sheet, speed) in the same table.
- **What a preview may show is Apple's call, not ours**: the screen as
  captured, with no zoom, backdrop, cards or captions. The README's "The
  previews" section lists the rules. The teaser has none of those limits.

## After a run

Nothing counts as done until someone has watched it, and that someone is the
maintainer. Movement cannot be judged from stills: a sheet of frames has
already passed legs as walking that barely moved, and the maintainer caught it
on playback.

1. **Check the file against the spec.** Run `ffprobe -show_entries
   stream=codec_name,width,height,r_frame_rate,level:format=duration`. It should
   show H.264, the device's exact size, 30fps, 15–30s and an AAC track. The
   sizes are iPhone 886×1920, iPad 1600×1200, Mac 1920×1080 and Vision Pro
   3840×2160 (Level 5.1; the others 4.0).
2. **Look at a contact sheet** for the story and for anything wrong in a frame,
   such as a home screen, a keyboard, or a sheet that never opened:
   `ffmpeg -i f.mp4 -vf fps=1,scale=320:-1,tile=6x4 -frames:v 1 sheet.png`.
3. **Spot-check the touches** at full size over a second or two around a
   press. The ring should land on the control as it lights, not after it.
4. **Hand the films over.** Copy them out of `$TMPDIR` to somewhere the
   maintainer can open, give the links, and say what cannot be judged from
   stills. For previews, remind them of two things at upload: the poster frame
   defaults to 5s, which is mid-story, so pick the finished drawing; and
   Vision Pro's Level 5.1 file has to be checked against what App Store Connect
   accepts.

## When a run fails

- **A simulator script stopped.** The reason is in the result bundle:
  `xcrun xcresulttool get test-results tests --path <raw>/test.xcresult`, then
  the "Failure Message" nodes. `failure.txt` beside it is the screen the test
  last saw, with frames. Read it before guessing.
- **The Mac script stopped.** Its runner is sandboxed, so there is no
  `failure.txt`. Export the attachments (`xcresulttool export attachments`):
  XCTest's own UI hierarchy dumps and screen recording are among them.
  "Timed out while enabling automation mode" means the password dialog went
  unanswered.
- **Vision Pro gives `TBNotReady` every time.** Something is recording the
  simulator while the app launches. The recorder must start after `TBReady`.
- **A film cuts to the home screen, or its touches drift.** The conversion has
  lost `-fflags +igndts`.
- **A cut is far longer than expected.** Something keeps drawing frames:
  usually a blinking caret outside a `typing` span, or on the Mac a recording
  judged by frames rather than by content.
