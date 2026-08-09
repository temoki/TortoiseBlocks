# appstore/

The source of truth for the App Store listing. `fastlane deliver` pushes it to
App Store Connect (#42).

```
metadata/<locale>/*.txt            the text, one file per field
screenshots/<platform>/<locale>/   ios/ and macos/, one directory per locale
screenshot-sources/                the documents the captures were shot from
```

`<locale>` is an App Store Connect locale code (`en-US`, `ja`), not the app's
`en` / `ja` string-catalog code. `ios` and `macos` name the two listings: there
is no ipadOS — iPad is a display type under iOS, and deliver files a screenshot
by its pixel size.

## Running it

The key never lives in the repository. Locally:

```sh
export ASC_ISSUER_ID=…            # App Store Connect → Users and Access → Integrations
export ASC_KEY_ID=…
export ASC_PRIVATE_KEY_PATH=~/…/AuthKey_XXXXXXXXXX.p8

bundle install
bundle exec fastlane metadata_check      # the files alone, no network, no key
bundle exec fastlane ios metadata_diff   # what is live, against what is written
bundle exec fastlane ios metadata_push   # upload (mac for the other listing)
```

In CI it is the **App Store Metadata** workflow, run by hand from the Actions
tab: pick a platform, and tick *apply* to upload rather than diff. It reads the
same three values from secrets, with the .p8 base64-encoded into
`ASC_PRIVATE_KEY` because a GitHub secret is one line and a PEM is not.

`metadata_diff` exists because **deliver has no dry run for metadata** — it
either uploads, or renders an HTML page for a human to approve. So the diff
goes the other way: it downloads what is live into a temporary directory and
compares. Screenshots are not part of it; their diff is `git status`.

Neither lane uploads a binary or submits for review. Builds reach TestFlight
from Xcode Cloud on a `v*` tag, and the last step in front of App Review stays
a human clicking it.

Two things a first push runs into, both learned the hard way:

- **App Review Information must exist before deliver will run at all.** deliver
  reads it without a rescue, and an app that has never had it gets `No data`
  from the API and a stack trace. Fill in the contact details in App Store
  Connect once — it is required for submission anyway
- **`metadata_diff` reports What's New as a difference until the second
  release**, because App Store Connect does not take it for a first version and
  deliver correctly skips it. Two fields, one per locale, and they are noise
  rather than a problem

## Files and limits

Limits are in **characters**, not bytes, and `fastlane/metadata_check.rb`
enforces them: on every pull request, and again from `metadata_push`, so a
hand-run upload cannot skip it. It is plain Ruby with no gems, so CI runs it as
`ruby fastlane/metadata_check.rb` without waiting for `bundle install`.

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
- The name and subtitle belong to the app and the rest to one version of one
  platform. deliver knows which is which, so they share a directory here

## Screenshots

- The sizes are the ones Apple accepts as-is: **iPad 13-inch landscape
  2752×2064** and **Mac 2880×1800**. A reshoot has to keep the window sizes
  that produced them
- Order comes from the leading number in the filename. Ten per locale, at most
- **Carry no alpha channel** (`magick <f> -alpha off -define png:color-type=2
  <f>`). Fully opaque is not enough — the channel alone can get a screenshot
  refused
- Capture the whole screen on Mac, not the window: a window-only capture has
  transparent rounded corners and shadow. Set the *system* language to the
  locale being shot, too — switching only the app's language leaves the menu
  bar in the other language
- **deliver uploads every screenshot twice on a first upload**, reproducibly.
  It matches local against live by MD5, and Apple has not computed that
  checksum seven seconds after the PUT, so each image looks missing and the
  whole set is retried. `metadata_push` therefore does not end with deliver:
  it waits for the checksums, deletes the duplicates, sorts the set by
  filename, and fails if what is live still does not match what is on disk

## Not managed here

Price and availability, App Privacy (the data-collection declaration), age
rating, category, submitting for review, and uploading the build.
