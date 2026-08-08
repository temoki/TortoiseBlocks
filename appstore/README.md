# appstore/

The source of truth for the App Store listing. App Store Connect is updated
from here (#42).

Every directory and file name is **App Store Connect's own vocabulary**, so
nothing needs a mapping table. `ios` / `macos` are `Platform` values — there is
no ipadOS, iPad is a display type *under* iOS, resolved from the image size —
and `en-US` / `ja` are ASC locale codes, not the app's `en` / `ja`
string-catalog codes.

```
app/<locale>/          appInfoLocalizations   — shared across versions
version/<locale>/      appStoreVersionLocalizations — per version
screenshots/<platform>/<locale>/
screenshot-sources/    the documents the captures were shot from
```

## Files and limits

Limits are in **characters**, not bytes. Trailing whitespace and the final
newline are stripped before upload.

| File | App Store Connect field | Limit |
| --- | --- | --- |
| `app/<locale>/name.txt` | Name | 30 |
| `app/<locale>/subtitle.txt` | Subtitle | 30 |
| `app/<locale>/privacy_url.txt` | Privacy Policy URL | — |
| `version/<locale>/description.txt` | Description | 4000 |
| `version/<locale>/keywords.txt` | Keywords | 100 |
| `version/<locale>/promotional_text.txt` | Promotional Text | 170 |
| `version/<locale>/release_notes.txt` | What's New in This Version | 4000 |
| `version/<locale>/support_url.txt` | Support URL | — |
| `version/<locale>/marketing_url.txt` | Marketing URL | — |

- **Keywords are comma-separated with no spaces** — a space counts against the
  100. Words already in the name or subtitle are indexed anyway, so don't
  repeat them here
- **Promotional text is the only field that can be replaced without review.**
  Changing the description, by contrast, takes a new version
- **What's New is not shown for a first release.** The first
  `release_notes.txt` is a placeholder for the second version onward
- Adding `version/ios/<locale>/` or `version/macos/<locale>/` overrides
  `version/<locale>/` for that platform. Nothing needs it yet

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

## Not managed here

Price and availability, App Privacy (the data-collection declaration), age
rating, category, submitting for review, and uploading the build (that stays
with Xcode Cloud).
