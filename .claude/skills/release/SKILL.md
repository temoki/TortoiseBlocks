---
name: release
description: >-
  Everything about shipping Tortoise Blocks and everything the public sees:
  cutting a v* tag, Xcode Cloud archives and TestFlight, the App Store Connect
  listing in appstore/ and Tools/appstore.rb (asc) that pushes it,
  accessibility nutrition labels, bundle identifiers and build audience, and the
  published website in site/ (the landing page and the privacy policy). Load
  this before tagging a release, editing the store text, pushing the listing, or
  touching
  site/. **Making** the screenshots is the `screenshots` skill; this one covers
  pushing them.
---

# Releasing Tortoise Blocks

These are the decisions and the traps, in the order they bite. Each one was
paid for once already.

**`site/` is the public website, `docs/` is the repository's own
documentation.** Anything served at `tortoiseblocks.hiraku.space` lives
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
**It can also deploy a ref that is not main**, which is the escape hatch when
the site has to move while main is ahead of what has shipped — 1.1.0's review
window was spent serving 1.0.0's landing page from a branch, with only
`privacy.html` carried across so App Review could read why the app senses the
room. What that costs is a line in the `github-pages` environment: it lists the
refs allowed to deploy (`main` and `gh-pages`), and anything else fails in two
seconds with `not allowed to deploy to github-pages due to environment
protection rules`, naming the ref and nothing else. Tags are never in that list
by default — and a tag's `site/` is the site as of the tag, not as of the
release, which for `v1.0.0` meant a "Coming soon" page whose badge pointed at
GitHub.
**The site is GitHub Pages under a custom domain** (#151):
`tortoiseblocks.hiraku.space`, a CNAME to `temoki.github.io` in the
`hiraku.space` zone (Google Cloud DNS), set as the repository's Pages custom
domain — in the settings, not a `CNAME` file, which an Actions deploy ignores.
It used to be `temoki.github.io/TortoiseBlocks/`, and every link to that still
works because GitHub answers the old address with a 301 to the new one — but
*only* while the custom domain is set on Pages. That is why this site stays on
GitHub Pages although `hiraku.space` itself and its other subdomains are on
Firebase Hosting: moving it there would leave the old address to a
meta-refresh page at best, and every App Store listing and README link to it
with no redirect a crawler treats as a move. The site sits at the host root
now, so its own links stay relative and the only absolute URLs are the ones
that must be — hreflang, `og:url`, `og:image`, JSON-LD, the sitemap, and the
listings' `marketing_url.txt` / `privacy_url.txt`. A domain change touches
exactly those. `hiraku.space` is a verified domain on the GitHub account, so
no other account can claim one of its subdomains while the CNAME points at
GitHub.
**One file in `site/` is not part of the site.**
`googlec3508f6a7924162b.html` is Google Search Console's proof of ownership for
the URL-prefix property `https://temoki.github.io/TortoiseBlocks/` — the
address the site had before the custom domain — and its
entire content is the one line Google generated. Do not tidy it, rename it, or
wrap it in HTML: the check reads the file's contents and the name has to match
what is inside. It is a file rather than the `<meta name="google-site-verification">`
alternative for one reason — the landing page's `<head>` is rewritten every
release, and a tag living there is exactly what a rewrite drops silently, taking
the verification with it; Search Console re-checks periodically and un-verifies
when the proof stops answering. Nothing links to it, and nothing should.

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

**The site is registered with Google Search Console, and the SEO is three
files' worth of plumbing rather than copywriting.** The landing page went a
month without appearing in a search, and the first suspicion — that something
was blocking crawlers — was wrong: there is no `robots.txt` anywhere, no
`noindex`, no `X-Robots-Tag`, and the repository is public. It had simply never
been registered, and one thing about it was genuinely broken. **A crawler
renders the page, so it negotiates like a browser** — Googlebot's
`navigator.languages` is `en-US` — and the Japanese `<section>` therefore goes
`display:none` on the one URL anyone links to. The Japanese page was not
ranking badly; it did not exist. The fix keeps every decision above intact:
hreflang alternates naming `?lang=en`, `?lang=ja` and the bare URL as
`x-default`, real `<a href="?lang=…">` links in both footers because a
`<select>` is not something a crawler can follow, and a `data-description` on
each section beside the `data-title` that was already there — so adding a
language is still a code, an `<option>` and a translated `<section>`.
**There is deliberately no `rel=canonical`.** It would have to differ per URL,
and one file cannot say three things: a static one pointing anywhere folds the
other two into it and un-indexes the Japanese page, while a script-written one
is the case Google says not to rely on. hreflang carries the relationship, and
that is what it is for. The `?lang=` spelling is not free to change either —
it is what `appstore/metadata*/*/marketing_url.txt` and `privacy_url.txt`
already point at, so a move to `/ja/` paths would mean re-pushing both
listings.
`site/sitemap.xml` lists nine URLs rather than three, because an hreflang set
has to name every variant from every variant. It carries no `lastmod`: the site is
deployed by hand at release time, so the date would go stale the first time
someone forgot it, and Google ignores a lastmod it cannot trust. **It is
submitted in Search Console and announced from `site/robots.txt`** — and the
second only became possible with the custom domain. A `robots.txt` is read at
the *host* root and nowhere else; under `temoki.github.io/TortoiseBlocks/` that
root belonged to no repository here, and a file in `site/` would have been
served, ignored, and mistaken for working. On its own host the site's root is
the host's root, so now it counts.
The JSON-LD `SoftwareApplication` block is the weakest of these and is kept
honest on purpose: every value in it is checkable against the App Store
listing, `LICENSE`, or the specs table on the page itself, and there is no
`aggregateRating` — nor may one ever be added that nobody left.

**The landing page is written for parents and teachers**, not for the kid and
not for a developer — the technical account lives in the README. Three things
about it are decisions rather than taste. The App Store badge is Apple's own
artwork, served from `site/` rather than Apple's CDN (a site that promises no
tracking should make no third-party request), and its `href` is *the* single
place the store URL lands: `apps.apple.com/app/id6798677334`, with no country
code, so Apple sends each visitor to their own storefront. Its screenshots are downscaled
copies of `appstore/screenshots/`, produced by `Tools/screenshots.rb` — see the
`screenshots` skill, which owns that pipeline and the reasons behind it; what
matters here is that the page weighs ~1MB rather than ~4.7MB because of it.
And each Japanese paragraph is one
source line: a newline between two CJK characters is not reliably collapsed
away, and shows up as a gap mid-sentence.

**`appstore/` is the store listing, named in App Store Connect's own
vocabulary** (#42). Full-size captures live at
`appstore/screenshots/<platform>/<locale>/`, and every path component is
literally a value the API takes: `ios` / `macos` are the `Platform` enum —
**there is no ipadOS**, iPad is a *display type* under iOS — and `en-US` /
`ja` are ASC locale codes, not the app's `en` / `ja` string-catalog codes, so
the uploader reads platform and locale straight off the path. The one
exception is `ios_duo/`, the iPhone Duo's captures: iOS too, in a directory of
its own only because fastlane could not file that size. Order comes from the
leading number in the filename, and the sizes are the ones Apple accepts as-is
(iPad 13-inch landscape 2752×2064, Mac 2880×1800), so a reshoot has to keep the
window sizes that produced them. The two documents the captures were shot from
sit in `appstore/screenshot-sources/`, deliberately *outside* `screenshots/`.

**A display type is not named after the size it holds**, so do not infer one.
Read back off the live listing (2026-10-09, #154), the five this app files into
are `APP_IPAD_PRO_3GEN_129`, `APP_IPHONE_67`, `APP_IPHONE_DUO`, `APP_DESKTOP`
and `APP_APPLE_VISION_PRO` — and `APP_IPHONE_67` is where the 6.9-inch
captures this rig shoots (1320×2868) landed, under a name that reads 6.7.
That reading is now a table: `DISPLAY_TYPES` in `Tools/appstore.rb` maps
directory and pixel size to display type, every set is uploaded with its type
*named*, and a size the table does not know stops the push. That is the
opposite of what deliver did — it inferred the type from the size, which is
how a Vision Pro capture (3840×2160, the size of an Apple TV one) could be
filed as `APP_APPLE_TV`. A new size is a new row, checked by reading the
listing back after its first push.

**Making the captures is the `screenshots` skill** — the rigs
(`Tools/ipad-shots.rb`, `Tools/visionos-shots.rb`), the flatten-and-optimise
pass every reshoot has to end with, and the traps that produce a picture of the
wrong thing. Nothing reaches App Store Connect without going through it: every
source this project shoots from writes an alpha channel, which Apple refuses.
**App previews go up with the rest, and are committed.** The `film` skill
makes them and `Tools/film/previews.rb` copies each finished film to
`appstore/previews/<name>.mp4` (`iphone`, `ipad`, `mac`, `vision`). They are
in git so that CI can send them like everything else — keeping them out would
have meant an API key on whichever Mac made them. The cost is history: about
22MB a full set, again on every reshoot, which is why previews are remade only
when the maintainer asks, and why Vision Pro's 4K film is encoded at about
4Mbps — half what the first upload carried, at no difference a 1:1 crop could
show. A push sends what is committed, the same video to both locales, and
reports a missing one rather than reshooting it. They are silent on the store;
music only ever goes on copies made for elsewhere (YouTube). The text is `appstore/metadata/<locale>/`, one file per field — **except
visionOS**, which is pushed from `appstore/metadata-visionos/` instead (#53).
That split is not tidiness: the App Store shows a Vision Pro shopper the
visionOS description and nothing else, and the app is a different product
there — a viewer for drawings made on iPad and Mac, with no editing in it at
all — so the shared description would open by telling that shopper to drag
blocks into a program, the one thing they cannot do. Three fields in those
directories are **app**-level in App Store Connect rather than version-level
(`name.txt`, `subtitle.txt`, `privacy_url.txt`), so every push writes the same
ones and whichever runs last decides them for all three listings; they are kept
byte-identical between the two directories and `metadata_check` fails if they
drift. A platform's text is also the first thing to go stale when the app
changes shape: the visionOS copy described "the same three panes in a window"
for as long as visionOS was the iPad app in a window (#11), and stayed that way
through the rewrite that made it a viewer.

**asc pushes it** (#154), the third uploader this listing has had. The first
was designed as a zero-dependency Swift executable (#42) and abandoned about 900
lines in, before it compiled: authentication, the resource graph and the
screenshot reserve/chunk/commit dance, all unverifiable without a live key. The
second was fastlane's deliver, which cost one directory move because the field
names here were deliver's from the start — and it is why they still are. deliver
was dropped for what it could not do: it filed screenshots by inferring the
display type from the pixel size and did not know the iPhone Duo's, so that set
went up by hand; its `overwrite_screenshots` deleted *every* set of a locale, so
the hand-uploaded Duo set had to go up again after each push; it took no app
previews at all; and it had no dry run for metadata. asc
([asccli.sh](https://asccli.sh), a single Go binary, MIT) does each of those,
and `Tools/appstore.rb` is a thin plain-Ruby wrapper around it with two
commands, `diff` and `push`, per platform. The repository has no Gemfile any
more. Three choices in that wrapper are measured rather than taste:

- **Text goes through `asc migrate import`, screenshots never do.** It reads the
  deliver layout as-is, but it skips a screenshot whose *file name* is already
  live, and a reshoot keeps its names — so the new picture would never reach
  the store. Screenshots go a set at a time through `asc screenshots upload
  --replace --device-type …`, which empties only the set it is given; a set
  that already matches by checksum and order is not touched.
- **Previews go through `asc video-previews upload --replace`**, not `migrate
  import`, which adds a new video *beside* the old one rather than replacing it.
- **The diff is an export, compared.** `migrate import --dry-run` lists what it
  would send without reading the live text, so `diff` runs `asc migrate export`
  of the version into a temporary directory and compares it file by file —
  against the version being prepared if there is one, the one on sale if not.

`Tools/metadata_check.rb` is the part of #42 that never needed the network: it
measures character limits and the three things a screenshot must be, because
App Store Connect reports those only mid-upload during a run nobody does often.
`push` runs it first, so a hand-run upload cannot skip it, and CI runs it as
`ruby Tools/metadata_check.rb` on every pull request — plain Ruby, no gems.
asc wants the key file to be its owner's alone (`chmod 600`); a looser one is
refused with "private key file is too permissive". asc also sends anonymous
usage telemetry by default (command, duration, exit code) to its developer;
that is left on deliberately — the no-tracking promise is about the app people
use, not the tools that ship it.

**Trust the listing, not the log.** Pushing 1.0.0 through deliver produced two
successes that were not: one run reported "Successfully uploaded screenshots"
having written *nothing* (a relative path resolved against the wrong
directory), and the next wrote *everything twice* (it matched local against
live by MD5 seconds after the upload, before Apple had computed the checksum).
Both were found by reading the listing back. So **a push ends with the diff and
fails unless it is clean**, giving App Store Connect up to five minutes to
compute the checksums of what was just sent before it compares. **What's New
does not exist until the second release on a platform**, because the field
belongs to an update, so text written there cannot reach the store however many
times it is pushed and the diff reports it every run. Two permanent phantom
lines is how a diff people read becomes a diff people skip, so for a platform's
first version its `release_notes.txt` is left **empty** and
`MetadataCheck::MAY_BE_EMPTY` allows that one field in that one directory.
**Write the notes and delete the exemption together** when the platform takes
its second version — an update with no What's New is refused, and by then it is
the exemption that would be hiding the empty file. (visionOS was the last to
need it; the table is empty now.)
**And a visionOS app cannot be submitted until App Motion is answered.** It is
a required *app*-level property for every visionOS app — App Store Connect →
App Information → App Motion, alongside the other fields the app keeps rather
than the version — and it is nowhere in `appstore/`, so a push cannot set it
and `metadata_check` cannot miss it. Nothing warns of it until the submission itself refuses, with a
sentence about violent or frequent motion and no mention of where to go. The
answer here is **"No, this app doesn't contain high motion"**, and it follows
from Apple's own rule rather than from modesty: the test is whether *the
virtual camera* moves without the user moving their head or body, and this app
never moves it. The drawing is placed once and stays where it was put; the
tortoise walking the paper is an object a twelfth of the sheet's width, and
changing the placement moves the sheet, not the viewer. Once answered it stays
answered — this is a first-visionOS-submission cost, like the version record
and What's New.

**visionOS is a third listing, spelled three different ways** (#11). It is a
native app on the xrOS SDK, not "Designed for iPad", so App Store Connect gives
it its own platform version — which the app record must carry before a push
can write to it. Its text is its own (`appstore/metadata-visionos`, above); its
screenshots are `appstore/screenshots/visionos`, filed as
`APP_APPLE_VISION_PRO` by name. To asc the platform is `VISION_OS` (`IOS`,
`MAC_OS` for the others), and `--device-type` takes the display type without
its `APP_` prefix. The captures come from the simulator at exactly 3840×2160,
the simulated room and all, which is what visionOS screenshots look like anyway
(the `screenshots` skill has the rig). And no new identifier is needed — a
visionOS app signs against the **iOS** bundle-ID platform, so the App IDs the
iPhone/iPad build already registered are the ones visionOS uses.

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
Differentiate Without Color and Sufficient Contrast — and, **from 1.2.0,
Reduced Motion**, declared in App Store Connect with the 1.2.0 submission:
every animation reads `accessibilityReduceMotion` through
`App/Views/Motion.swift` (#70–#78). That declaration is a promise about every
later version too, so a new animation goes through `Motion` rather than
around it. It declines Voice Control
(untested) and captions/audio descriptions (there is no media).

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
drift, since it requires one distinct value across every configuration in the
project). **That is every configuration, including targets that ship
nothing**: adding the UI test target put a fifth and sixth `MARKETING_VERSION`
in the file at Xcode's default `1.0`, and the next tag would have opened with
`MARKETING_VERSION is not the same everywhere` — a red check on the release,
for a test bundle nobody installs. It is carried at the app's version rather
than exempted, because the alternative is teaching a `grep` which targets to
believe.
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
