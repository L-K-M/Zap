# UNJAILED — custom, un-squircled icons for the Zap switcher

*A design study, July 2026. **Phases 1, 2 and 4 (§10) are implemented.** Phase 3
was deliberately skipped and phase 5 is not built. Sections describing shipped
behaviour are marked; everything else is still design.*

macOS 26 puts every app icon in the same rounded-rectangle mask. Zap draws its own
icon row, so it is not obliged to. This document works out what it would take for
Zap to show the icon a user actually wants — the app's original artwork, a file
they picked, or something they found through a built-in image search — and what
the real constraints are.

**Verification caveat** (same as `ANALYSIS.md`): this was written in an
environment with no macOS toolchain and no Tahoe machine. Every claim about
system behaviour carries a confidence marker. The high-confidence ones still want
ten minutes on a real Mac before anyone writes code against them.

---

## 1. What "squircle jail" actually is

Since macOS 26 (Tahoe), the system composites every app icon into one fixed
superellipse. Apps that shipped Tahoe-native artwork fill that shape. Everything
else — the entire back catalogue of Mac icons, including the free-form ones the
platform was known for — gets **scaled down and inset onto a grey plate**, then
masked. The effect is system-wide: Finder, the Dock, open/save panels, even
Safari's extension settings ([Lapcat Software][lapcat]).

The trigger is not "is this icon an odd shape". A community finding on Apple's
developer forums ([thread 797971][forum]) pins it to a single alpha threshold on
the artwork's edge pixels:

| Edge-pixel alpha | Result |
|---|---|
| ≥ 253 | Clipped to the squircle, fills the shape |
| ≤ 252 | Forced onto the grey plate, scaled down and inset |

Which is why *square* legacy icons get jailed too: ordinary anti-aliasing leaves
edge pixels at alpha 240–250. The workaround developers pass around is a script
that slams every pixel to alpha 255 before packing the `.icns`.

As of July 2026 there is still no opt-out. macOS 27 "Golden Gate" is in beta for
a Fall 2026 release; it walks back a fair amount of Liquid Glass, but not this
([Daring Fireball][df2026]). Users are left with third-party de-jailers
([SquircleNoMore][sqnm]) and the Finder trick — manually re-assigning an icon
through Get Info, which the system honours unmasked ([Simon B. Støvring][simonbs]).

### 1.1 Why Zap is unusually well placed here

Every existing de-jailer works by **writing into other apps** — extended
attributes, an `Icon\r` file, a resource fork. That approach inherits a pile of
problems, all of which Zap gets to skip:

| Existing de-jailers | Zap |
|---|---|
| Must modify the target app bundle | Reads only; substitutes at draw time |
| Can't touch `/System/Applications` or App Store apps ([SquircleNoMore][sqnm]) | Reads any bundle it can `stat` — Apple's own apps included |
| Reverts when the app updates | Keyed by the app itself, survives updates |
| Leaves Finder-info/resource-fork detritus that trips `codesign` | Writes nothing into any bundle |
| Needs an undo story | Delete a preference row |

Zap already owns every pixel of its icon row (`OverlayView.iconCell`). Swapping
the `NSImage` is the entire mechanism. That is the single most important design
fact in this document: **un-jailing in Zap is a presentation choice, not a system
mutation.**

The corollary is that it only fixes Zap. The Dock and Finder stay jailed. That is
a real limitation and should be stated plainly in the UI, not buried.

---

## 2. Goals and non-goals

**Goals**
- Show original, un-masked app artwork in the switcher, automatically, with no
  configuration, no network, and no user effort.
- Let a user override any app's icon with a file of their own.
- Let a user *find* an icon without leaving Zap, from sources whose licensing and
  attribution are handled honestly.
- Keep it off the ⌘-Tab hot path. Zero added cost per keystroke.
- Degrade to today's behaviour whenever anything is missing, broken, or off.

**Non-goals**
- Changing icons anywhere outside Zap's own panel (see §11.1).
- Shipping artwork with Zap (see §11.2).
- Generating icons (see §11.4).
- Any new third-party dependency (`AGENTS.md`: "prefer system frameworks").

---

## 3. The resolution ladder

One ordered chain, evaluated per bundle ID, first hit wins:

```
  ┌─ 3. User override ──────── a file the user picked or searched for
  │                            (Application Support/Zap/Icons/<bundleID>.png)
  ├─ 2. Original artwork ───── read out of the app bundle, unmasked
  │                            (Contents/Resources/*.icns, or Assets.car)
  └─ 1. System icon ────────── NSRunningApplication.icon — today's behaviour,
                               and whatever the system hands us
```

Level 2 is the headline. It is offline, needs no configuration, no API key, no
network, and no user decisions — and it fixes the complaint for every app that
predates Tahoe, which is most of them. Level 3 exists for the apps Level 2 can't
help: the ones that shipped genuine squircle artwork, where there is no original
shape left to recover.

A per-app setting can pin any app to a specific rung (including "system icon,
leave it alone").

---

## 4. Level 2 — recovering the original artwork

### 4.1 Where it lives

An app bundle declares its icon one of several ways. Resolution order:

| # | Info.plist key | Where the art is | How to read it | Confidence |
|---|---|---|---|---|
| 1 | `CFBundleIconFile` | `Contents/Resources/<name>.icns` | `CGImageSourceCreateWithURL` — `com.apple.icns` is a first-class ImageIO type | High |
| 2 | `CFBundleIconName` | Compiled into `Contents/Resources/Assets.car` | `Bundle(url:)?.image(forResource:)` — the documented API reads the bundle's asset catalog | Medium |
| 3 | `CFBundleIconFiles` | Loose PNGs (Catalyst / iOS-on-Silicon) | Direct file read | Medium |
| 4 | *(none)* | Any `*.icns` in `Contents/Resources` | Glob + pick the largest | Medium |

Notes worth carrying into the implementation:

- The extension is frequently **omitted** in `CFBundleIconFile` — `"AppIcon"`,
  not `"AppIcon.icns"`. Append it when missing. ([SquircleNoMore][sqnm] hit the
  same thing.)
- `Bundle.image(forResource:)` works on *any* bundle, not just `Bundle.main`, and
  unlike `NSImage(named:)` it does not consult the shared image cache. It is the
  public route into a foreign `Assets.car` — no CoreUI SPI, no `assetutil`
  subprocess. **Verify this on a Tahoe machine before building on it**; it is the
  load-bearing unverified claim in this document.
- Tahoe-era apps built with Icon Composer compile a layered `.icon` into
  `Assets.car`. Whether `image(forResource:)` flattens it, returns the light
  variant, or returns nothing is unknown. Treat a nil result as "fall through to
  Level 1", not as an error.
- Reading is not blocked by SIP. SIP stops *writes* to `/System`. Zap can read
  Finder's and Safari's artwork the same as anyone's — which is exactly where the
  existing de-jailers give up.

### 4.2 Deciding whether substitution is even worth it

*(Implemented: `IconShapeClassifier`, `AlphaMask`.)*

Naively swapping in the raw artwork makes some icons *worse*. A modern full-bleed
square icon, un-masked, becomes a hard-cornered square — sharper corners than
anything else on screen. So classify the artwork's alpha channel first:

| Class | Test | What to do |
|---|---|---|
| **Free-form** | Alpha bbox < canvas, or corners transparent in a non-superellipse way | Substitute. This is the classic Mac icon; the whole point. |
| **Plate** | Alpha fills a rounded rectangle (Big Sur era) | Substitute. This is what most people mean by "give me my icon back". |
| **Full-bleed** | Alpha bbox == canvas and corners opaque | Substitute *and* apply Zap's own corner mask, radius configurable — otherwise it reads as a hard square. |
| **Already squircle** | Alpha profile matches the Tahoe superellipse | Don't bother. Nothing to recover; keep the system icon. |

This is pure arithmetic over an alpha channel with no AppKit involved, so it is
straightforwardly unit-testable against synthetic bitmaps (§9). It also gives
Settings something honest to say per app: *"Original artwork available
(free-form)"* vs *"Already square — nothing to un-jail"*.

**Correction from implementing it: "plate" and "already squircle" are one class.**
Two of the four rows above cannot be told apart. Measured on the 64² grid the
classifier samples, over two metrics — the fraction of its own bounding box the
shape fills, and how far the corners round off along the diagonal:

| Shape | Fill ratio | Corner reach |
|---|---|---|
| Opaque square | 1.000 | 0.000 |
| Rounded rect, r = 0.225 × side (Big Sur plate) | **0.957** | **0.113** |
| Superellipse, n = 5 (Tahoe squircle) | **0.951** | **0.113** |
| Circle | 0.788 | 0.273 |

A 0.6% gap in fill ratio and none at all in corner reach — inside the noise of
anti-aliasing and resampling. The intuition that a superellipse is "visibly
rounder" than a Big Sur plate is wrong; that is the point of the superellipse.
Any threshold splitting those two rows would be a coin flip presented as a
measurement, so they are reported as one **rounded-square** class.

The merge costs nothing, which is why it is the right call rather than a
concession: both rows take the *same action* in the table above (substitute), and
substituting genuinely Tahoe-native artwork draws the same picture the system
would have drawn from it. The boundaries that do change what appears on screen —
hard square vs rounded, rounded vs free-form — are wide, and those are the ones
the classifier is actually deciding.

The shipped classes are therefore **free-form**, **rounded-square**,
**full-bleed** and **empty**, the last being "no readable alpha at all", which is
the real "nothing to do here" case. `ZapTests/IconShapeClassifierTests` asserts
both the separations and the non-separation, so if a future macOS makes the two
shapes distinguishable the test that merged them is the one that fails.

### 4.3 What Level 2 cannot fix

- Apps that shipped Tahoe-native squircle artwork. There is no earlier shape in
  the bundle. Level 3 or nothing.
- Apps with no icon at all (generic document icon).
- Anything whose artwork lives somewhere unenumerated — Safari "Add to Dock" web
  apps keep icons in a container, not a bundle.

---

## 5. Level 3 — bring your own icon, and finding one

### 5.1 Picking a file

`NSOpenPanel`, `allowedContentTypes` from the accept-list in §6. Zap is
unsandboxed, so no security-scoped bookmarks are needed; the file is copied into
Zap's own storage immediately anyway (§7), so a later move or delete can't break
anything.

Drag-and-drop onto a row in Settings should work too — `.dropDestination` is
already wired up elsewhere in the codebase. Note that a drag *from a browser*
carries a URL (or raw image data) on the pasteboard rather than a file, which is
a meaningfully different ingestion path and a more important one than it first
appears — see §5.3.

### 5.2 The search problem, honestly

"Built-in image search" sounds like one feature and is actually four decisions:
which corpus, whose API key, what licence, and what leaves the machine.

The obvious first instinct is **general web image search** — a Google Images box
inside Zap. It is the right instinct on coverage: a curated icon corpus has tens
of thousands of icons, the web has everything, and if someone wants a Companion
Cube for Terminal the web definitely has one. It also has a real answer to the
objection that web results are opaque JPEGs, which is the next section. It runs
into a different wall.

**Every general web image search API has closed or gone behind a credit card in
the last 18 months.**

| Provider | Status, July 2026 |
|---|---|
| Bing Image Search | **Retired 11 Aug 2025**, with the rest of the Bing Search family ([1][bingdead]) |
| Google Custom Search JSON | **"Closed to new customers"**, and the service **shuts down 1 Jan 2027** — [Google's own docs][gcse]. Existing customers get 100 queries/day free. |
| Brave Search API | Images endpoint exists; the 2,000/month free tier was **removed in February 2026**, replaced by prepaid credits with a **card required and no spending cap** |
| SerpApi / scraper-as-a-service | Live, ~$50/month, and a legally grey resale of someone else's results |
| DuckDuckGo | No official API; the endpoint people use is undocumented and against its terms |
| SearXNG | Self-host, or hammer a stranger's public instance |

So the honest position is not "a curated corpus is nicer than the web". It is
that **there is no free, keyless, durable general image search left to build
on** — and designing a July 2026 feature on an API that new users cannot sign up
for and that dies in five months would be malpractice.

**Corpus survey, for what remains.**

| Source | Corpus | Key? | Free limit | Format | Fit |
|---|---|---|---|---|---|
| **[macOSicons.com][mi]** | ~30k community macOS app icons, indexed by app name | Yes | **50 requests/month**; €4.99 / 1,000 after | PNG + `.icns` | ★★★★★ — purpose-built for exactly this |
| [Iconify][iconify] | ~300k icons, 200+ open sets (incl. `logos`, ~2k full-colour brand marks) | **No** | Generous public API, MIT | SVG only | ★★★☆☆ — needs a rasteriser |
| [SVGL][svgl] | ~400 curated brand logos, light/dark variants | **No** | Public, open source | SVG only | ★★☆☆☆ — small, needs a rasteriser |
| [Openverse][ov] | CC-licensed media, photo-weighted | No (optional OAuth) | 100/day, 5/hour anonymous | Raster | ★★☆☆☆ — wrong corpus for icons |

**Conclusions.**

1. **macOSicons is the primary provider.** It is the only *live* source whose
   corpus is this problem: someone has already drawn an un-squircled Safari icon,
   and it is filed under "Safari".
2. **A shared API key is not viable.** 50 requests/month free means one Zap user
   exhausts the quota in an afternoon. The model has to be **bring-your-own-key**:
   Settings links to the macOSicons dashboard, the user pastes a key, Zap stores
   it in the **Keychain** (not `UserDefaults`). Search is simply unavailable until
   they do. That is the honest constraint — the alternative is Zap paying per
   user, which a free open-source utility can't.
3. **Iconify is the keyless fallback** and unlocks a much larger corpus, but only
   once SVG rasterisation exists (§6.3). Sequence it after macOSicons.
4. **Keep the provider behind a protocol.** `IconSearchProvider` costs nothing
   now and means that if a viable general provider appears — or Zap ever gets a
   backend to hold a key — it slots in without touching anything else.

### 5.3 What survives from "just search the web": the transparency filter

The strongest argument for web search was never the raw index — it was that
Google Images can *filter* it. The Custom Search API exposed exactly the
parameters this feature wants ([reference][gcseparams]):

| Parameter | Value | Why it matters here |
|---|---|---|
| `imgColorType` | **`trans`** | **Transparent background only.** This is the whole ballgame — it is what turns "a page of opaque JPEG screenshots" into "a page of alpha-channel PNGs". |
| `imgType` | `clipart` | Excludes photos and stock imagery; icon-shaped art is clipart-shaped |
| `fileType` | `png` | Alpha-capable container |
| `imgSize` | `large` / `xlarge` | Clears the 512 px floor in §6.2 |
| `rights` | `cc_*` | Licence filtering — known to be unreliable, but better than nothing |

The API is going away; **the idea is not**. Two things to carry forward:

- **"Transparent only" is the correct default filter for any image source Zap
  ever searches.** It is the machine-checkable form of "is this un-jailable?" —
  and it is the same question the alpha classifier in §4.2 asks of bundle
  artwork. One concept, two places.
- **The search can happen where search is still free: the user's browser.**
  Google Images itself has the transparency filter in its UI (Tools → Color →
  Transparent), unmetered and with no key. So the pragmatic substitute for
  in-app web search is **in-app web search *ingestion***: the user searches in
  the browser and **drags the image straight onto the app's row in Settings**, or
  pastes a URL. Zap does the fetch, validation (§6), normalisation (§8.3),
  storage and attribution capture.

That last point deserves emphasis, because it is a better trade than it looks:
it delivers most of the value of a built-in web search for a fraction of the
code, with **no API key, no quota, no ToS exposure, no per-user cost, and
nothing that can be shut down underneath it**. The user does the one part they
are better at than any API — judging whether an icon looks right — and Zap does
the parts it is better at.

The cost is honest and worth stating: accepting a dragged URL means fetching
remote bytes, which pulls the untrusted-decode hardening in §6.4 forward from
phase 3 to phase 2. Phase 1's "no network code at all" property is worth keeping
intact for one release, so URL ingestion is sequenced after it (§10).

**A cheap keyless bonus.** Most bundle IDs are reverse-DNS:
`com.apple.Safari` → `apple.com`, `com.tinyspeck.slackmacgap` → `tinyspeck.com`.
Reversing the first two components and fetching `/apple-touch-icon.png` costs
nothing and needs no provider. In practice apple-touch-icons are square and
opaque — so this yields a *correct* icon that is still a square, which does not
help the actual complaint. Worth ~30 lines as a last-resort suggestion in the
search sheet; not worth more.

### 5.4 Attribution and licensing

macOSicons requires crediting **both** macOSicons.com and the individual icon's
author, and prohibits commercial use on the free tier ([docs][mi]). Zap is free
and open source, so the commercial clause is satisfied, but attribution is a
hard requirement with a concrete design consequence:

- The search response carries `credit` and `creditUrl`. **Persist them into the
  manifest** (§7) at save time, not just at display time.
- Settings shows the credit on the app's row and links out.
- The About tab lists every credited source currently in use.
- Exported icon packs carry the credits with them.

If attribution can't be plumbed through, the provider shouldn't be built.

### 5.5 Privacy

A search sends the app's name to a third party, which is a small but real
disclosure of what the user has installed. (Drag-and-drop ingestion per §5.3 has
none of this exposure — the query never leaves the browser the user typed it in.)
Rules:

- **Never search automatically.** Not on launch, not on first run, not "let's
  pre-fetch icons for your top ten apps". Only in response to a click.
- Prefill the query with the app name but let the user **edit it before sending**.
- **The bundle-ID list never leaves the machine**, under any circumstance.
- Show what will be sent, and to whom, before the first search of a provider.
  **Shipped as once, persisted** rather than once per session: a notice shown every
  time is one that stops being read, and the acknowledgement is kept per provider
  because the disclosure is each provider's own statement of what it sends.
- No telemetry. Zap has none today (see the switch counter in `AboutView` —
  local-only) and this must not be where that changes.

---

## 6. Constraints on supported images

**Shipped: what a stored icon is keyed by.** Not the bundle identifier, which
does not identify an app. Site-specific-browser wrappers — Coherence, Unite, the
Chrome/Electron family — ship one app bundle per site and every one of them reports
the browser's identifier, so `/Applications/Claude ★.app`, `/Applications/CodeNomad.app`
and `/Applications/CodeNomad Dev.app` were all `com.google.Chrome` and shared a
single override between them. `IconIdentity` writes new overrides under the bundle
*path*, which is unique, and reads fall back to the identifier so every icon set
before the change still resolves — nothing was migrated. The trade is that an app
which moves loses its icon where an identifier would have followed it; updating in
place doesn't move it, and re-picking the file fixes it.

### 6.1 Formats

macOS reads a lot through ImageIO, but "readable" and "should be accepted" differ.

| Format | Read? | Accept | Why |
|---|---|---|---|
| PNG | ✅ | **Preferred** | Alpha, lossless, universal. Canonical storage format. |
| ICNS | ✅ | Yes | Multi-resolution; what app bundles actually contain. Pick the largest rep by *pixel* size. |
| TIFF | ✅ | Yes | Alpha, lossless. |
| PDF | ✅ | Yes | Core Graphics renders it natively — a **vector path that needs no SVG support**. Rasterise on import. |
| HEIC | ✅ | Yes | Alpha supported. |
| WebP / AVIF / JPEG-XL | ✅ read-only | Yes | ImageIO decodes but does not encode; re-encode to PNG on save. |
| GIF / APNG | ✅ | Frame 0 only | Animation in a switcher that appears for 200 ms is a novelty, not a feature. |
| JPEG / BMP | ✅ | Accept with a **warning** | No alpha. The result is a rectangle — i.e. still jailed, just differently. Say so in the UI. |
| ICO | ✅ | Yes | Low-res in practice; warn under 128 px. |
| **SVG** | ❌ by ImageIO | Yes, rasterised | Not decodable by `NSImage`/ImageIO; `SVGRasterizer` renders it first (§6.3). Reaches Zap by every route a bitmap does — chosen file, dropped file, dragged link, search result. |

Detect the type from the **decoded data** (`CGImageSourceGetType`), never from the
file extension or the server's `Content-Type`.

**Shipped:** `IconImport` is the single door for anything the user supplies. It
sniffs the bytes, sends SVG to `SVGRasterizer` and everything else to
`IconImageValidator`, and is `async` because the first of those drives a web view.
`IconStore` takes an image rather than a file URL for the same reason: a synchronous
URL-decoding convenience is a second ingestion path that silently refuses every SVG,
which is exactly how SVG came to be rejected with "that file isn't an image Zap can
read" after §6.3 had already shipped.

### 6.2 Dimensions, geometry, memory

| Constraint | Value | Rationale |
|---|---|---|
| Minimum | 128 × 128 px (warn), 64 hard floor | `iconSize` reaches 128 pt = 256 px at 2×; anything smaller is visibly mushy |
| Recommended | ≥ 512 px | Covers 128 pt @2× with headroom |
| Stored master | 1024 px longest edge | One resample from any real source; ~4 MB in memory, ~200 KB as PNG |
| Hard decode ceiling | 8192 px/axis, 40 MP | Decompression-bomb guard (§6.4) |
| Max source file | 10 MB | Sanity |
| Aspect ratio | clamp to 1:2 … 2:1 | A 10:1 banner destroys the row's rhythm |
| Alpha | not required, strongly wanted | Without it there is nothing to un-jail |

`iconSize` is clamped 24…256 in `Preferences`, and 48…128 by the Appearance
slider. On a 2× display the worst case is 512 px, so a 1024 px master never needs
upsampling.

### 6.3 SVG — the awkward one

`NSImage` cannot decode SVG. Neither can ImageIO. The options:

| Approach | Verdict |
|---|---|
| Bundle SVGKit / librsvg / resvg | ❌ `AGENTS.md`: "Don't add heavy dependencies" |
| CoreSVG SPI (`CGSVGDocumentCreateFromData`) — what [SDWebImageSVGCoder][sdsvg] uses | ⚠️ Works, and the repo already tolerates SPI for Developer ID (`_AXUIElementGetWindow`, `CGS*` — see `ANALYSIS.md §9`). But it is undocumented, throws on gradients and non-system fonts, and slams the App Store door further shut. |
| **Offscreen `WKWebView` snapshot** | ✅ **Recommended.** Public API, ~100 lines, no dependency. |
| Rasterise server-side | ❌ Needs a server Zap doesn't have |

The WKWebView route runs **once per icon, in a Settings sheet** — never on the
switcher's hot path — and the result is baked to PNG on disk, so the cost is paid
exactly once. Rendering fetched SVG in a web view does mean parsing untrusted
markup, so: `allowsContentJavaScript = false`, a navigation delegate that denies
every navigation, and load from a `data:` URL so the document has no origin and
no network. Then `takeSnapshot(with:)` at 1024 px.

**Shipped, with two corrections the design didn't anticipate.** Navigation policy
only covers page-level navigations, so it does nothing about a subresource — an
`<image href="https://tracker/…">`, a CSS `url(…)`, an external `<use>`. That gap
was first closed with a `WKContentRuleList`, which turned out to be the wrong
tool: compiling one can fail on a given machine, and the fail-closed branch then
refused *every* SVG, on every route, with an error that read as a complaint about
the file. It is now a `Content-Security-Policy` meta tag on the generated document
(`default-src 'none'`, inline styles and `data:` images excepted) — no compile
step, no on-disk store, no async path that can fail. Separately, a `WKWebView`
that is never added to a window does not paint, so the snapshot came back empty;
the view is hosted in an offscreen window for the length of the render.

Until that exists, Iconify and SVGL simply aren't offered. Phase it (§10).

### 6.4 Handling untrusted image data

Zap is unsandboxed with hardened runtime enabled. ImageIO parses in-process, so a
decoder bug in a downloaded file is an in-process compromise of an app that holds
Accessibility permission. That deserves more than a shrug:

- **Check before decoding.** `CGImageSourceCopyPropertiesAtIndex` reports
  `kCGImagePropertyPixelWidth`/`Height` from the header. Reject oversize images
  *before* allocating anything.
- **Decode through `CGImageSourceCreateThumbnailAtIndex`** with
  `kCGImageSourceThumbnailMaxPixelSize = 1024` and
  `kCGImageSourceCreateThumbnailFromImageAlways`, which bounds the output
  allocation regardless of what the header claims.
- **Cap the download** at 10 MB by streaming, not by trusting `Content-Length`.
- **Re-encode to PNG on save.** What lands on disk is then Zap's own output —
  the original container, its EXIF, its ICC oddities and any format-specific
  payload never persist.
- Convert to sRGB (or Display P3) at import so downstream alpha analysis and
  tinting operate in a known space.
- Prefer `CGImageSource` over `NSImage` for anything analytical.
  `NSImage`'s representation-picking and lazy loading make "how many pixels is
  this, really" surprisingly hard to answer.

The thorough fix is decoding inside a short-lived XPC service that can be
sandboxed to nothing. That is the right answer eventually and too much for v1;
the caps above are the pragmatic floor. Note it as a known limitation rather than
pretending it away.

---

## 7. Storage and data model

`UserDefaults` is a plist read at launch; image blobs do not belong in it.

```
~/Library/Application Support/Zap/
  Icons/
    manifest.json
    com.apple.Safari.png
    com.googlecode.iterm2.png
```

```jsonc
{
  "version": 1,
  "entries": {
    "com.apple.Safari": {
      "file": "com.apple.Safari.png",   // resolved and bounds-checked, never trusted
      "source": "search",               // file | search | originalArtwork
      "provider": "macosicons",
      "credit": "Some Person",
      "creditURL": "https://macosicons.com/…",
      "license": "CC BY 4.0",
      "addedAt": "2026-07-31T10:00:00Z",
      "bleed": 0.08,                    // per-app overrides of the global defaults
      "trim": true
    }
  }
}
```

**Validate on load exactly the way `AppearancePreset.apply(to:)` does** — clamp
every number, fall back on every unparseable enum, and additionally: reject any
`file` containing `/` or `..`, resolve it, and assert the result is inside
`Icons/`. A manifest can arrive from an imported pack, so it is untrusted input.

New `Preferences` keys (defaults in parentheses):

| Key | Type | Default |
|---|---|---|
| `iconSourceMode` | `system` / `original` / `originalPlusCustom` | `original` on macOS ≥ 26, `system` below |
| `iconBleed` | Double 0…0.15 | 0.08 |
| `iconTrimTransparentEdges` | Bool | true |
| `iconShadow` | Bool | true |
| `iconSearchProvider` | String | `macosicons` |

The macOSicons API key goes in the **Keychain**, keyed by service name — not in
`UserDefaults`, and never in an exported preset or pack.

**Icon packs.** A `.zapicons` file is a zip of exactly the layout above. Export
and import mirror the existing theme-preset flow in `AppearanceView` almost
line-for-line. This is also the clean answer to licensing: Zap redistributes no
artwork; users share packs among themselves, and attribution rides along in the
manifest.

---

## 8. How it fits the existing code

### 8.1 New module (`PLAN.md §10` structure)

```
Zap/Icons/
  IconResolver.swift          bundleID → NSImage; the only thing the hot path touches
  BundleArtwork.swift         §4.1 — reads .icns / Assets.car out of an app bundle
  IconShapeClassifier.swift   §4.2 — alpha analysis, pure
  IconNormalizer.swift        §8.3 — trim / scale / bleed / shadow, pure geometry
  IconStore.swift             §7   — Application Support layout, manifest I/O
  IconManifest.swift          §7   — Codable + validation (mirrors AppearancePreset)
  IconImageValidator.swift    §6   — format / dimension / security gate
  Search/
    IconSearchProvider.swift  protocol: query → [IconSearchResult]
    MacOSIconsClient.swift    §5.2 (mirrors GitHubReleaseClient's shape)
    IconSearchResult.swift
Zap/Settings/
  IconsView.swift             §8.4
  IconSearchSheet.swift
```

### 8.2 The hot path

Today `AppInfo.init?(runningApplication:)` reads `app.icon` directly, and
`AppListProvider.currentApps()` runs on every ⌘-Tab. `ANALYSIS.md §P1` already
flags that everything expensive happens on the main thread on the keystroke path;
this feature must not add to that.

- `IconResolver` holds a cache keyed by `IconIdentity`, **pre-rendered
  at the current icon size × the max backing scale factor**, with the shadow baked
  in (a SwiftUI `.shadow` on 40 icons per frame would show up — cf. `§P3`).
- Warmed at launch and on preference change, off the main thread. Invalidated on
  `iconSize` change (debounced) and on `NSWorkspace` app-launch notifications.
- Lookup is a dictionary hit with a `nil` fallback to `app.icon`. Same cost as
  today.
- Masters stay on disk. 40 apps × 1024² RGBA in memory would be 160 MB; 40 apps
  at display size is under 10 MB.
- Cleanest injection point: hand `AppListProvider` an `IconResolver` and let it
  fill `icon:`. `AppInfo` stays a dumb value type, and `==` already ignores
  `icon`, so overrides can't perturb identity or the MRU.

Stale-artwork invalidation: key the Level-2 cache on `(bundle path, mtime,
CFBundleVersion)` so an app update re-reads its artwork.

### 8.3 Layout — the part that is genuinely fiddly

Free-form icons are the point, and free-form icons break a row built for squares.

Today: `iconCell` renders into a square `iconSize × iconSize` frame with
`.aspectRatio(.fit)`, `.padding(8)`, and `IconRowMetrics.cellWidth = iconSize + 16`.

Four consequences:

1. **A wide icon looks smaller.** `.fit` in a square frame letterboxes it, so a
   2:1 icon renders at half the visual weight of its neighbours. Fix: normalise
   by **alpha-bounding-box area**, not by bounding box — match the *ink*, so a
   circle and a square read as the same size. This is what Apple's own icon grid
   does, and it is pure arithmetic, so it is testable.
2. **Trim first.** Source art often carries transparent margin. Trim to the alpha
   bbox before scaling, or the icon floats small inside its cell.
3. **Bleed needs room.** A hammer or a hand *should* poke out of its cell — that
   is the classic Mac look. Between adjacent icon images there is
   `spacing (12) + 8 + 8 = 28 pt`, so ~14 pt each side is free before neighbours
   collide. Vertically, the cell's own 8 pt padding is free and `contentPadding`
   (default 20) absorbs a little more before the panel's `clipShape` cuts.
   **Put a `bleed` term into `IconRowMetrics`** and derive `cellWidth` from it, so
   `OverlayView` and `OverlayWindowController`'s scroll maths keep sharing one
   source of truth — exactly why `IconRowMetrics` exists.
4. **Two clips will bite.** `HorizontallyScrollable` calls `.clipped()`, and the
   panel calls `.clipShape(RoundedRectangle(…))`. Bleeding art gets cut at both.
   Growing `cellWidth` with the bleed handles the row; the panel needs
   `contentPadding` to be at least the vertical bleed, or the bleed to be clamped
   against it.

Also: the hidden-app badge is positioned `.bottomTrailing` on the icon's frame,
and the drop-target ring strokes the padded cell. Both need re-checking against a
bleeding, trimmed icon — the badge in particular can end up floating in space
beside a narrow icon.

And silhouette: free-form art on a translucent blurred panel loses its edges.
A soft drop shadow (which Apple's own icons get for free from the plate) restores
it — baked into the cached bitmap, not applied per frame.

### 8.4 Settings

A new **Icons** tab (`SettingsView` already has six; a seventh is fine).

```
┌ Icons ─────────────────────────────────────────────────────┐
│ Icon source:  ( ) System icons                             │
│               (•) Original app artwork when available       │
│               ( ) Original artwork + my custom icons        │
│                                                             │
│ ⓘ Applies to Zap's switcher only. The Dock and Finder       │
│   keep showing the system's icons.                          │
│                                                             │
│ [🔍 Search apps                                         ]   │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │ 🧭  Safari          Original artwork (free-form)   [⋯]  │ │
│ │ 🖥️  iTerm2          Custom · macOSicons · @someone  [⋯]  │ │
│ │ 📝  Notes           Already square — nothing to fix [⋯]  │ │
│ └─────────────────────────────────────────────────────────┘ │
│ [Import Pack…] [Export Pack…]        [Reset all icons]      │
└─────────────────────────────────────────────────────────────┘
```

The `⋯` menu: *Use original artwork · Choose File… · Search for an icon… · Use
system icon · Reset*.

List **installed** apps, not just running ones. `ExclusionsView` currently only
lists running apps plus offline exclusions — the same gap `ANALYSIS.md §U5`
files. Solving it once here would be reusable, and merging Exclusions and Icons
into a single "Apps" tab is the obvious eventual shape (out of scope for a first
pass, worth noting).

Layout controls (bleed, trim, shadow, full-bleed corner radius) belong in
**Appearance**, next to the existing icon-size slider, where the live preview
already shows the result. The preview builds three synthetic `AppInfo`s with SF
Symbols — swapping in one free-form, one plate, and one full-bleed sample would
demonstrate all three classes at once.

---

## 9. Testing

CI is `macos-14` / Xcode 16.2 — **it cannot run macOS 26 at all**, so none of the
Tahoe-specific behaviour is CI-testable, even in principle. Split accordingly.

**Unit-testable (headless, deterministic):**

| Target | Test |
|---|---|
| `IconManifest` | Codable round-trip; clamping; unknown fields; **path traversal in `file` rejected** |
| `IconShapeClassifier` | Synthetic `CGImage`s → expected class: opaque square → `.fullBleed`, rounded plate → `.plate`, circle → `.freeform`, superellipse → `.alreadySquircle` |
| `IconNormalizer` | Alpha-trim rect; equal-ink scaling (circle vs square land at the same visual weight); bleed clamping |
| `IconRowMetrics` / `IconRowGeometry` | `cellWidth(iconSize:bleed:)`; row width, `maxScroll`, `centeredOffset`, and `fade` stay correct with bleed > 0 |
| `IconImageValidator` | Accept/reject table from §6.2 |
| `BundleArtwork` | Resolution order against **synthetic bundles built in a temp dir** — a hand-written `Info.plist` plus a generated `.icns`. Covers the extension-omitted case. |
| `MacOSIconsClient` | Canned JSON fixture, exactly the `GitHubReleaseTests` pattern |

**Manual only, on a real Tahoe machine** — and these are the ones that decide
whether the feature works at all:

- Does `NSRunningApplication.icon` actually return masked artwork? (§1)
- Does `Bundle.image(forResource:)` actually read a foreign `Assets.car`? (§4.1)
- What does it return for an Icon Composer `.icon`? (§4.1)
- Does reading `/System/Applications/Safari.app` work unprivileged? (§1.1)
- Visual: mixed classes in one row; bleed against both clips; light vs dark
  panels; Reduce Transparency; 2× and 1× displays.

---

## 10. Phasing

| Phase | Scope | Ships |
|---|---|---|
| **1** ✅ | `BundleArtwork` + `IconShapeClassifier` + `IconResolver` + `IconStore`/manifest + Icons tab with Original / System / Choose File… | **The actual fix.** Offline, no network code, no API key, no new formats, no dependency. Most users need nothing else. |
| **2** ✅ | `IconNormalizer` + bleed/trim/shadow in `IconRowMetrics` + Appearance controls; **drag-a-URL / drag-from-browser ingestion** + the §6.4 untrusted-decode hardening it requires | Makes mixed shapes look deliberate rather than ragged, and lets the user search the web where searching the web is still free (§5.3) |
| **3** | macOSicons search (BYO key), attribution plumbing, privacy sheet | The "don't make me leave the app" part — strictly optional once phase 2 exists |
| **4** ✅ | WKWebView SVG rasterisation → Iconify / SVGL providers | Large keyless corpus |
| **5** | `.zapicons` pack export/import | Sharing, and the same shape as theme presets |

Phase 1 stands alone and is worth shipping alone. Everything after it is optional
polish on a problem already solved for the majority of apps.

**What phase 1 actually shipped**, against the plan above:

- All five components, plus `AlphaMask` (the sampling step, split out of the
  classifier so the arithmetic is testable without Core Graphics) and
  `IconImageValidator` — pulled forward from phase 2, because *Choose File…*
  accepts a file from the user and the §6.4 decode bounds are the whole reason
  that is safe to do. No network code came with it, so phase 1 keeps its
  "no network at all" property.
- Full-bleed corner masking (§4.2) with a **fixed** radius rather than a
  configurable one. §8.4 puts that control on the Appearance tab next to the
  other layout knobs, and those arrive together in phase 2.
- Per-app pinning to the system icon, stored as a manifest entry with no file.
  §3 asks for a per-app pin to *any* rung; only the "leave it alone" rung is
  reachable so far, which is the one with a use case.
- **Not** the four-class shape table — see the correction in §4.2.

**What phase 2 shipped**, and the one place it improves on §8.3:

- `IconNormalizer` (trim → equal-ink scale → bleed clamp → baked shadow),
  `iconBleed`/`iconTrimTransparentEdges`/`iconShadow` on the Appearance tab, and
  drag-from-browser ingestion with `RemoteIconFetcher` counting bytes as they
  arrive rather than trusting `Content-Length`.
- **The two clips stop being a problem.** §8.3 item 4 expects bleeding art to be
  cut by `HorizontallyScrollable`'s `.clipped()` and the panel's `clipShape`, and
  proposes clamping the bleed against `contentPadding`. Deriving the cell as
  `max(imageExtent, iconSize + cellPadding)` avoids the situation entirely: the
  image is always *contained* by its cell, so neither clip can reach it, and no
  clamp against `contentPadding` is needed. What the art bleeds past is the
  selection highlight — which is the look §8.3 is actually after. At the default
  bleed this also costs no extra row width, matching the "~14pt each side is free"
  observation. A test asserts containment across every icon size and bleed.
- The hidden-app badge is inset back to the nominal icon frame rather than the
  bled one, which is the "floating in space beside a narrow icon" case §8.3 flags.
- Not done: `iconBleed`/trim/shadow are **not** in `AppearancePreset`. Adding
  non-optional fields to it would break importing older theme `.json` files, so a
  shared theme doesn't carry them yet; it wants optional fields with defaults.

**What phase 4 shipped, and why phase 3 was skipped rather than deferred.**

- `SVGRasterizer` (offscreen `WKWebView`, JavaScript off, a navigation delegate
  that permits exactly one in-memory load, non-persistent data store),
  `IconSearchProvider` + `IconSearchResult`, the keyless `IconifyClient`, and a
  search sheet carrying §5.5's rules structurally: prefilled-but-editable query,
  nothing sent until the button is pressed, disclosure shown before the first
  search of a provider (persisted, so once rather than once per sheet), bundle
  identifier never sent.
- **Skipping phase 3 costs nothing**, which §12 question 3 already suspected.
  Phase 3 was macOSicons behind a BYO key; phase 4's Iconify is keyless, so the
  provider protocol got built and exercised by a *real* provider rather than by a
  paid one nobody had signed up for. If macOSicons is ever wanted it slots in
  behind the same protocol.
- Attribution is on `IconSearchResult` rather than looked up at save time, so the
  credit reaches the manifest — §5.4's condition for a provider being allowed to
  exist at all. Iconify's `/search` returns bare `prefix:name` strings, so set
  names and licences come from `/collections`, fetched once per session.
- **`loadHTMLString(_:baseURL: nil)` rather than a `data:` URL.** §6.3 asks for
  `data:` so the document has no origin; `baseURL: nil` gives the same property
  (no origin, nothing to resolve a relative URL against) and is the supported way
  to hand `WKWebView` in-memory markup.
- **Unverified:** whether `takeSnapshot` preserves the SVG's transparency. The
  page is transparent and `underPageBackgroundColor` is clear, but if a snapshot
  comes back composited on white the alpha classifier will read every rasterised
  icon as `.fullBleed` and corner-mask it — degraded, not broken. Wants a real
  machine, like the rest of §9's manual list.
- SVGL is **not** built. It is ~400 logos against Iconify's ~300k, and the same
  protocol takes it whenever someone wants it.

Still open from §12, unchanged by shipping: the load-bearing
`Bundle.image(forResource:)` claim (question 1) has still never been run against a
foreign `Assets.car`. The code treats a `nil` from it as "fall through", so if the
claim is false the feature quietly degrades to `CFBundleIconFile` apps rather than
breaking — but the framing in §4.1 would need rewriting.

Note the shape of 2 vs 3: **phase 2 makes phase 3 optional.** Once a user can
drag an image in from a browser, an in-app search saves them a window switch and
nothing else. If phase 3 never gets built, the feature is still complete.

---

## 11. Rejected alternatives

### 11.1 Replacing icons system-wide (`NSWorkspace.setIcon`)

Tempting — it would fix the Dock and Finder too — and rejected for v1:

- It writes into other apps' bundles. A cosmetic switcher preference should not
  mutate the filesystem outside Zap.
- It leaves `com.apple.FinderInfo` / resource-fork detritus, which is precisely
  the "resource fork, Finder information, or similar detritus not allowed"
  `codesign` failure ([1][seticon]).
- It reverts on every app update, so it needs a re-application daemon.
- It cannot touch App Store apps or system apps ([SquircleNoMore][sqnm]) —
  whereas Zap's read-only approach handles those fine.
- It needs a real undo story, including for apps since uninstalled.

Worth revisiting as an explicit, clearly-labelled opt-in later. Not as the
mechanism.

### 11.2 Shipping an icon set with Zap

Trademark and licence exposure on every logo, a much larger binary, and it goes
stale. Users share packs instead (§7).

### 11.3 Cropping the grey plate out of the system icon

Detect the plate, crop, upscale. Brittle (the plate is a colour, not a marker),
lossy (the inset artwork is already downscaled), and strictly worse than reading
the source artwork, which is right there in the bundle.

### 11.4 Building on a general web image search API

Evaluated properly (§5.2) rather than dismissed, because the coverage argument is
genuinely strong and Google Images' `imgColorType=trans` filter answers the
"web results have no alpha" objection cleanly.

It fails on availability, not on merit. Bing's API is retired; Google's Custom
Search JSON API is closed to new customers and **shuts down 1 Jan 2027**
([Google's docs][gcse]) — a new Zap user could not obtain a key today even if
Zap shipped the integration tomorrow; Brave dropped its free tier in Feb 2026 and
now wants a card on file with no spending cap. What's left is paid scrapers.

The salvage is §5.3: keep the transparency filter as a design principle, and let
the browser be the search box.

### 11.5 AI icon generation

macOSicons exposes `/editor/generate`. It needs a paid key, produces
unpredictable results, and Zap has no LLM/inference story of any kind. Out of
character for a switcher.

### 11.6 CoreSVG SPI

See §6.3. The repo already tolerates SPI, but WKWebView is public, roughly the
same amount of code, and doesn't throw on gradients.

---

## 12. Open questions

1. **Does the load-bearing claim hold?** `Bundle.image(forResource:)` against a
   foreign `Assets.car` on Tahoe. If it doesn't, Level 2 covers only
   `CFBundleIconFile` apps — still a large majority, but the framing changes.
2. **Default on or off?** Un-jailing changes the switcher's appearance without
   being asked. Arguments for on-by-default on macOS ≥ 26: it is a *restoration*,
   and the users who install a third-party switcher are the ones who dislike the
   mask. Arguments for off: surprise. Leaning on, with a first-run note.
3. **Is BYO-key search worth building at all?** Phase 1 solves the stated problem
   offline and phase 2 covers the remainder by letting the browser do the
   searching (§5.3). Phase 3 then asks users to sign up for a third-party service
   to save a window switch. Leaning towards: build the protocol, defer the
   provider, and see whether anyone actually asks for it.
4. **Bleed default.** 8 % is a guess. Needs eyes on a real row.
5. **Per-app or global?** This document allows per-app `bleed`/`trim` overrides.
   That may be one knob too many for a first pass.

---

## Sources

- [macOS Tahoe forces all app icons into iOS squircles — Lapcat Software][lapcat]
- [Squircle app icons on macOS 26 — Apple Developer Forums (alpha 252/253 threshold)][forum]
- [How To Bring Back Oddly Shaped App Icons in macOS 26 Tahoe — Simon B. Støvring][simonbs]
- [SquircleNoMore — Tweaking4All][sqnm]
- [Apple Should Eliminate the App Icon 'Squircle Jail' — Daring Fireball, July 2026][df2026]
- [macOSicons API documentation][mi]
- [Iconify API][iconify] · [SVGL][svgl] · [Openverse API][ov]
- [Custom Search JSON API — "closed to new customers", shutdown 1 Jan 2027][gcse]
  · [image search parameters (`imgColorType`, `imgType`, `rights`)][gcseparams]
- [Bing Search API retirement, 11 Aug 2025][bingdead]
- [SDWebImageSVGCoder — CoreSVG-based SVG rendering][sdsvg]
- [NSWorkspace setIcon and code-signing detritus — Apple Developer Forums][seticon]

[lapcat]: https://lapcatsoftware.com/articles/2025/6/2.html
[forum]: https://developer.apple.com/forums/thread/797971
[simonbs]: https://simonbs.dev/posts/how-to-bring-back-oddly-shaped-app-icons-on-macos-26-tahoe/
[sqnm]: https://www.tweaking4all.com/software/macosx-software/squirclenomore-getting-rid-of-the-ugly-macos-tahoe-icons-jail/
[df2026]: https://daringfireball.net/2026/07/eliminate_app_icon_squircle_jail
[mi]: https://docs.macosicons.com/
[iconify]: https://iconify.design/docs/api/
[svgl]: https://svgl.app/
[ov]: https://api.openverse.org/v1/
[bingdead]: https://cloro.dev/blog/bing-search-api-key/
[gcse]: https://developers.google.com/custom-search/v1/overview
[gcseparams]: https://developers.google.com/custom-search/v1/reference/rest/v1/cse/list
[sdsvg]: https://github.com/SDWebImage/SDWebImageSVGCoder
[seticon]: https://developer.apple.com/forums/thread/126175
