---
name: release
description: >-
  Everything about shipping Tortoise Blocks and everything the public sees:
  cutting a v* tag, Xcode Cloud archives and TestFlight, the App Store Connect
  listing in appstore/ and the fastlane lanes that push it, screenshots,
  accessibility nutrition labels, bundle identifiers and build audience, and
  the published website in site/ (the landing page and the privacy policy).
  Load this before tagging a release, editing the store text or screenshots,
  running fastlane, or touching site/.
---

# Releasing Tortoise Blocks

These are the decisions and the traps, in the order they bite. Each one was
paid for once already.

**`site/` is the public website, `docs/` is the repository's own
documentation.** Anything served at `temoki.github.io/TortoiseBlocks/` lives
in `site/`: `index.html`, the landing page, and `privacy.html`, the policy App
Review requires of every app, including one that collects nothing. `docs/`
holds README assets and architecture notes and is *not* published;
`appstore/` holds the full-size App Store captures (see below), and the site
carries its own downscaled copies rather than linking those. The split
is the reason `pages.yml` exists at all: GitHub's classic Pages builder accepts no source
but the repository root or `/docs`, so publishing any other directory takes a
workflow. **It runs on `workflow_dispatch` only** — publishing is a step of
the release, not of the merge, so the page describing a version cannot go live
before that version does; site changes land on main when they are ready and
are deployed by hand (Actions tab, or `gh workflow run pages.yml`) once the
release is out. Do not add a `push:` trigger back for convenience: that is the
timing this replaced. And `cancel-in-progress: false`, because a deploy
interrupted midway can leave the live site as a half-written artifact.
The policy page states what was *measured* — no accounts, no analytics, no
advertising or third-party SDK, no tracking, and no networking code anywhere
in the app or in TortoiseGraphics2 — which is also why no
`PrivacyInfo.xcprivacy` is needed: nothing here touches a required-reason
API, not even `UserDefaults`. That last one is **held on purpose and has
already had to be defended once**: #53's viewer read a debug launch flag with
`UserDefaults.standard.bool(forKey:)`, which is where a `-flag value` pair
normally arrives, and one debug read of it obliges the whole app to ship a
manifest declaring `CA92.1`. It now reads `ProcessInfo.processInfo.arguments`
instead — same launch command, no manifest. So the thing to re-check is not
only "a dependency or an `@AppStorage`": *any* `UserDefaults` call counts,
including a read, including one that only fires in development, because it is
compiled into the shipping binary. `NSWorldSensingUsageDescription` (#53) is
**not** on that list — a usage description is a permission, not a
required-reason API, and it changes the policy page rather than the manifest.
**Both pages read in one language**, chosen by
`?lang=` first, then `navigator.languages` in the reader's own order, falling
back to English; adding a language is a code in `LANGS`, an `<option>`, and a
translated `<section>`. Two rules hold it together: the site stores nothing (a
page promising no data collection has no business writing `localStorage`, so
the choice rides in the URL — which is also what gives App Store Connect its
per-localization URLs), and it never hides behind a script (the hiding rule
keys on an attribute only JavaScript sets, so with JavaScript off every
language renders in full). The landing page pays for that in bytes: each
language is a full copy of the page, screenshots included, and **the hidden
copy's images are fetched anyway** — an `<img>` with no layout box loads
eagerly, `loading="lazy"` and all (measured against a logging local server,
with and without a forced screenshot). So every visitor downloads both
languages' screenshots — ~1MB at ten of them, 1.1.0's count — and
quantization is what keeps that a non-issue. Only CSS `background-image` would actually skip them, and it is
not worth trading `<img alt>` on the page's content images to save one
language's worth of cached bytes.

**The landing page is written for parents and teachers**, not for the kid and
not for a developer — the technical account lives in the README. Three things
about it are decisions rather than taste. The App Store badge is Apple's own
artwork, served from `site/` rather than Apple's CDN (a site that promises no
tracking should make no third-party request), and its `href` is *the* single
place the store URL lands: `apps.apple.com/app/id6798677334`, with no country
code, so Apple sends each visitor to their own storefront. Its screenshots are downscaled
copies of `appstore/screenshots/`, quantized to 256 colors (`magick -dither None
-colors 256 -strip`) and then run through `oxipng -o max --strip safe`: flat app
UI loses nothing visible and the page drops from ~4.7MB to ~1MB — but check a
re-quantized shot by eye, since dithering *on* leaves visible speckle in the
toolbar shadows. The oxipng pass is a third of that saving and it is *lossless*,
so it goes over the store captures and `docs/` too (18.6% off everything, pixels
proved identical by hashing the decoded images before and after). Without it,
`magick` alone lands about 25% high: the 1.0.0 files were plainly made with some
such pass, so a set regenerated on a machine that has none comes out heavier for
no visible reason. And each Japanese paragraph is one
source line: a newline between two CJK characters is not reliably collapsed
away, and shows up as a gap mid-sentence.

**`appstore/` is the store listing, named in App Store Connect's own
vocabulary** (#42). Full-size captures live at
`appstore/screenshots/<platform>/<locale>/`, and every path component is
literally a value the API takes: `ios` / `macos` are the `Platform` enum —
**there is no ipadOS**, iPad is a *display type* under iOS, resolved from the
image size — and `en-US` / `ja` are ASC locale codes, not the app's `en` / `ja`
string-catalog codes. That is the whole point of the naming: an uploader reads
the directory names and needs no mapping table. Order comes from the leading
number in the filename, and the sizes are the ones Apple accepts as-is (iPad
13-inch landscape 2752×2064, Mac 2880×1800), so a reshoot has to keep the
window sizes that produced them. The two documents the captures were shot from
sit in `appstore/screenshot-sources/`, deliberately *outside* `screenshots/`.
The text is `appstore/metadata/<locale>/`, one file per field — **except
visionOS**, which is pushed from `appstore/metadata-visionos/` instead (#53).
That split is not tidiness: the App Store shows a Vision Pro shopper the
visionOS description and nothing else, and the app is a different product
there — a viewer for drawings made on iPad and Mac, with no editing in it at
all — so the shared description would open by telling that shopper to drag
blocks into a program, the one thing they cannot do. Three fields in those
directories are **app**-level in App Store Connect rather than version-level
(`name.txt`, `subtitle.txt`, `privacy_url.txt`), so every lane writes the same
ones and whichever runs last decides them for all three listings; they are kept
byte-identical between the two directories and `metadata_check` fails if they
drift. A platform's text is also the first thing to go stale when the app
changes shape: the visionOS copy described "the same three panes in a window"
for as long as visionOS was the iPad app in a window (#11), and stayed that way
through the rewrite that made it a viewer.

**fastlane pushes it, and a self-written tool did not.** The uploader was
designed as a zero-dependency Swift executable (#42) and abandoned about 900
lines in, before it compiled: what remained was the authentication, the resource
graph, and the screenshot reserve/chunk/commit dance — all of it unverifiable
without a live API key, and all of it already in `deliver`. The cost of
switching turned out to be one directory move, because the field names here
were fastlane's from the start. So the repository now has exactly one Ruby
dependency (`Gemfile`, `fastlane/Fastfile`), and it builds nothing, signs
nothing and submits nothing — two lanes per platform, `metadata_diff` and
`metadata_push`, with the helpers as `private_lane`s so `fastlane lanes` lists
only what is meant to be run. Note **deliver has no dry run for metadata**: it uploads, or
it renders an HTML page for a human. `metadata_diff` therefore runs the other
way, downloading the live text into a temporary directory and diffing it. The
one thing kept from the abandoned tool is the part that never needed the
network: `fastlane/metadata_check.rb` measures character limits and the three
things a screenshot must be, because deliver finds those only mid-upload during
a run nobody does often. It sits in `fastlane/` and `metadata_push` calls it
through a private lane, so a hand-run upload cannot skip it — but it is plain
Ruby that requires nothing from fastlane, and CI runs it as
`ruby fastlane/metadata_check.rb` on a bare checkout. That is the constraint
that shaped it: making a pull request wait for `bundle install` to read nine
text files would cost more than the check saves.

**Trust the listing, not deliver's log.** Pushing 1.0.0 for real produced two
successes that were not: one run reported "Successfully uploaded screenshots"
having written *nothing* (a relative `metadata_path` resolves against the
repository root, not the Fastfile, so it read a directory above the checkout
and found no locales), and the next wrote *everything twice* (deliver matches
local against live by MD5, Apple has not computed that checksum seconds after
the PUT, so every image looks missing and the set is retried). Both were found
by reading the listing back through spaceship. Hence two permanent guards in
`push_metadata`: it refuses to start unless both directories hold locale
subdirectories, and it ends by reconciling the screenshots — wait for the
checksums, delete duplicates, sort by filename, fail if live still differs from
disk. Two more traps sit outside our code: **App Review Information must exist
before deliver will run at all** (it reads it without a rescue and an app that
has never had it gets `No data`), and **What's New shows as a difference until
the second release**, because App Store Connect refuses it for a first version.
One more vocabulary mismatch to remember: deliver says `osx`, the Connect API
says `MAC_OS`, and passing the former to spaceship reports a missing version
that plainly exists.

**visionOS is a third listing, spelled three different ways** (#11). It is a
native app on the xrOS SDK, not "Designed for iPad", so App Store Connect gives
it its own platform version — which the app record must carry *before* either
lane will run (`get_edit_app_store_version` returns nil otherwise, and
`metadata_diff` stops with "No editable xros version"). The text is shared with
the other two, as it already was between iOS and macOS; only the screenshots
are per-platform. Then the vocabulary: **`visionos` names the screenshots
directory, `xros` goes to deliver, `VISION_OS` goes to spaceship**, and the
first of those is not a style choice. A Vision Pro capture is 3840×2160, the
same size as an Apple TV one, so deliver cannot resolve the display type from
the size and falls back to asking whether the *path* contains `vision`
(downcased) — name the directory after deliver's own platform value and every
screenshot is filed as `APP_APPLE_TV` on an app with no tvOS listing.
The captures need no staging: `xcrun simctl io <device> screenshot` on the
visionOS simulator writes exactly 3840×2160, the simulated room and all, which
is what visionOS screenshots look like anyway. They do carry an alpha channel,
so `-alpha off` applies here like everywhere else. And no new identifier is
needed — spaceship maps `xros` onto the **iOS** `BundleIdPlatform`, so the App
IDs the iPhone/iPad build already registered are the ones visionOS signs
against.

**A release is a `v*` tag** (#4). Xcode Cloud runs one `Release` workflow off
it — an Archive action per platform, each with a TestFlight internal
post-action bound to its own archive artifact. It carries no Build or Test
action: GitHub Actions has already run the lint, the Kit tests and both
platform builds on the way to main, and Xcode Cloud's 25 free compute
hours/month are the scarce resource, not GitHub's. The two never overlap
because `ci.yml` triggers on `branches`, which a tag ref does not match.
`ci_scripts/` is deliberately absent. The one thing that looked like it
needed a script does not: **Xcode Cloud sets the TestFlight build number from
`CI_BUILD_NUMBER` and ignores `CFBundleVersion`**, so the static
`CURRENT_PROJECT_VERSION = 1` never collides on a second upload the way it
would from a local archive. Nor does the team: the 0.1.0 release archived on
Xcode Cloud with `DEVELOPMENT_TEAM` empty and never once asked for one, so
the `ci_post_clone.sh` that would have written `Support/Local.xcconfig` from
a workflow environment variable is not needed either. Keep it that way.

**An Archive action's distribution audience decides whether the build can ever
be released.** Xcode Cloud's Archive actions carry `buildDistributionAudience`,
and while it says internal testing the build arrives as
`buildAudienceType: INTERNAL_ONLY` — which **cannot be added to an App Store
version**. Nothing says so usefully: App Store Connect lists the build in "Add
Build" and greys the row, and the API refuses with "The specified pre-release
build could not be added" and no reason. The diagnosis is
`GET /v1/builds/{id}` and reading `buildAudienceType`; the fix is
`APP_STORE_ELIGIBLE` on both Archive actions (readable back from
`GET /v1/ciProducts/{id}/workflows`). Existing builds can be flipped with a
PATCH, but re-cutting the tag is what makes the *next* one right — which is why
1.0.0 was tagged twice for the same commit tree, and only the second build
could be submitted.

**Accessibility Nutrition Labels stay drafts until the app ships.** Apple:
"You can only publish support for devices that have a live version on the App
Store." So the declaration is saved and stuck at `state: DRAFT` — visible
through `GET /v1/apps/{id}/accessibilityDeclarations` — and publishing it is a
step *after* the first release, not before. This app declares VoiceOver,
Larger Text (iPad only; the field is nil for Mac), Dark Interface,
Differentiate Without Color and Sufficient Contrast, and declines Reduced
Motion (`accessibilityReduceMotion` is read nowhere), Voice Control (untested)
and captions/audio descriptions (there is no media).

**Every bundle identifier must exist in the Developer portal before Xcode
Cloud can release.** Its automatic signing issues *profiles*; it cannot
*register* an identifier the way `-allowProvisioningUpdates` does locally
("Automatic signing cannot register bundle identifier …" / "No profiles for
… were found"). This bit the extension on the first real release, and it
lands in a confusing place: **the archive succeeds and the export fails**, so
the log says `** ARCHIVE SUCCEEDED **` a few hundred lines above the error.
A local archive is no evidence here — the one run before this used the
wildcard `iOS Team Provisioning Profile: *`, which covers a bundle ID that
was never registered. Neither is a green build on the other platform: macOS
uploaded to TestFlight from the same commit that failed on iOS. So when a new
extension or app-group identifier appears, register it at
developer.apple.com first (Identifiers → App IDs → explicit), and expect only
iOS to notice if you don't.
What *is* unlinked is the tag and the version it ships: nothing makes
`v0.2.0` and `MARKETING_VERSION` agree, and a mismatch uploads the old
version silently. `release-tag.yml` compares them (and catches app/extension
drift, since it requires one distinct value across all four configurations).
It cannot block the release — Xcode Cloud is already archiving — it only
makes the mistake loud while there is still a build to cancel. A suffix after
`-` is stripped before comparing: a marketing version is dotted numbers, a
tag has to be unique, and one version legitimately takes many TestFlight
builds, so `v0.1.0-beta2` and `v0.1.0-2` both release 0.1.0. The same workflow
then drafts a GitHub release, and only after that check passes — a tag whose
version does not match should not become one. `.github/scripts/release-notes`
composes the notes and is a script rather than inline YAML so it can be run
against any tag locally. It splits commits by whether they touched the app:
between 0.1.0 and 1.0.0, three of nineteen did, and a flat list buries them. A
release with no predecessor lists nothing — the first had 120 commits behind
it, which is a history, not a change log.
