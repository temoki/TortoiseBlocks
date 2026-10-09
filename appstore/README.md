# appstore/

The source of truth for the App Store listing. `Tools/appstore.rb` pushes it to
App Store Connect through [asc](https://asccli.sh), the App Store Connect CLI
(#42, #154).

```
metadata/<locale>/*.txt            the text, one file per field (iOS and macOS)
metadata-visionos/<locale>/*.txt   the visionOS listing's own text
screenshots/<platform>/<locale>/   ios/, ios_duo/, macos/ and visionos/
screenshot-sources/                the documents the captures were shot from
previews/                          the App Store previews — gitignored, see below
```

`<locale>` is an App Store Connect locale code (`en-US`, `ja`), not the app's
`en` / `ja` string-catalog code. `ios`, `macos` and `visionos` name the three
listings: there is no ipadOS — iPad is a display type under iOS. `ios_duo` is
iOS as well, the iPhone Duo's captures; it is a directory of its own only
because fastlane, which pushed this before asc, could not file that size.

Which display type a screenshot is filed under is **named, never inferred**:
`DISPLAY_TYPES` in `Tools/appstore.rb` maps each directory and pixel size to
one, and a size it does not know stops the push. Inference is what goes wrong
here — a Vision Pro capture is 3840×2160, the same as an Apple TV one, and the
6.9-inch iPhone captures are filed under `APP_IPHONE_67` because that is where
App Store Connect put them.

## Running it

The key never lives in the repository. Locally:

```sh
brew install asc
export ASC_ISSUER_ID=…            # App Store Connect → Users and Access → Integrations
export ASC_KEY_ID=…
export ASC_PRIVATE_KEY_PATH=~/…/AuthKey_XXXXXXXXXX.p8   # chmod 600 — asc refuses a looser one

ruby Tools/metadata_check.rb             # the files alone, no network, no key
ruby Tools/appstore.rb diff              # what is live, against what is written
ruby Tools/appstore.rb push              # upload, then diff again
ruby Tools/appstore.rb push ios          # …or just the listings named (ios, macos, visionos)
```

In CI it is the **App Store Metadata** workflow, run by hand from the Actions
tab: pick a platform, and tick *apply* to upload rather than diff. It reads the
same three values from secrets, with the .p8 base64-encoded into
`ASC_PRIVATE_KEY` because a GitHub secret is one line and a PEM is not, and it
installs a pinned, checksum-verified asc release. A runner has no previews, so
CI never sends them.

A diff compares against the version being prepared if there is one, and the
version on sale otherwise. A push needs an **editable version** for that
platform in App Store Connect, and stops with "No editable … version" until
one exists — the guard working, not a bug.

Neither uploads a binary or submits for review. Builds reach TestFlight from
Xcode Cloud on a `v*` tag, and the last step in front of App Review stays a
human clicking it.

**A push ends with a diff, and fails unless it comes back clean.** Trust the
listing, not the log: under fastlane, one push reported success having written
nothing, and another wrote every screenshot twice. The final diff gives App
Store Connect up to five minutes to compute the checksums of what was just
uploaded before it compares.

## How each part goes up

- **Text** through `asc migrate import`, which reads the deliver layout these
  directories already have. Name, subtitle and privacy URL are app-level in
  App Store Connect, so every push writes the same ones; `metadata_check` keeps
  the two directories agreeing on them
- **Screenshots** a set at a time — one locale, one display type — through
  `asc screenshots upload --replace`, which empties that set and no other. A
  set already matching by checksum and order is left alone. Not through
  `migrate import`: it skips a file whose *name* is already live, and a reshoot
  keeps its names, so the new picture would never replace the old one
- **Previews** from `previews/<name>.mp4` — `iphone`, `ipad`, `mac`, `vision` —
  through `asc video-previews upload --replace`, the same video to every
  locale. They are written by `Tools/film/previews.rb` and are not in git
  (megabytes each), so they exist only on the machine that made them. A missing
  video is reported and skipped, never reshot: the films are remade only when
  the maintainer asks for it. They go up silent; music is only for copies made
  elsewhere

## Files and limits

Limits are in **characters**, not bytes, and `Tools/metadata_check.rb`
enforces them: on every pull request, and again before every push, so a
hand-run upload cannot skip it. It is plain Ruby with no gems.

| File | App Store Connect field | Limit |
| --- | --- | --- |
| `name.txt` | Name | 30 |
| `subtitle.txt` | Subtitle | 30 |
| `description.txt` | Description | 4000 |
| `keywords.txt` | Keywords | 100 |
| `promotional_text.txt` | Promotional Text | 170 |
| `release_notes.txt` | What's New in This Version | 4000 |
| `privacy_url.txt` | Privacy Policy URL | — |
| `support_url.txt` | Support URL | — |
| `marketing_url.txt` | Marketing URL | — |

- **Keywords are comma-separated with no spaces** — a space counts against the
  100. Words already in the name or subtitle are indexed anyway, so don't
  repeat them
- **Promotional text is the only field that can be replaced without review.**
  Changing the description takes a new version
- **What's New is not shown for a first release.** The first
  `release_notes.txt` is a placeholder for the second version onward
- **iOS and macOS share one set of text**, release notes included, so a
  release that ships on one of them leaves the other's diff showing notes it
  has not published — expected, until that platform's next version

## Screenshots

- The sizes are the ones Apple accepts as-is: **iPad 13-inch landscape
  2752×2064**, **iPhone 6.9-inch 1320×2868**, **iPhone Duo unfolded
  2853×2007**, **Mac 2880×1800** and **Apple Vision Pro 3840×2160**. A reshoot
  has to keep the sizes that produced them
- Order comes from the leading number in the filename. Ten per display type, at
  most
- **Carry no alpha channel** (`magick <f> -alpha off -define png:color-type=2
  <f>`). Fully opaque is not enough — the channel alone can get a screenshot
  refused. `ruby Tools/screenshots.rb` does this after every reshoot
- Making them is the `screenshots` skill

## Not managed here

Price and availability, App Privacy (the data-collection declaration), age
rating, category, App Review Information, submitting for review, and uploading
the build.
