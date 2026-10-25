# Zap — Analysis & Backlog

The living record of what's wrong, what's missing, and what would be fun — the
document future work starts from. Entries are removed as they ship.

**Provenance.** Consolidates the July 2026 review (`claude-review.md`), the
earlier `awesome.md` review (both merged here), and the October 2026 pass
(`mimo.md`, a local working file since discarded). `ISSUES.md` stays as the
archived June 2026 review-and-resolution log.

**Scope.** Only unimplemented findings are listed. Entries fixed in merged PRs
(#16–#23 and earlier) are gone, as are entries with an open PR as of
2026-07→10: B6 (#53), B7+B9 (#58), B8 (#59), C3 (#60), C5 (#65), P2 (#64),
P4 (#57), P5 (#56), U4 (#55), and two small input nits (#61, #63). P1 is
*partially* addressed (#54 caches the scoped-display queries); what remains of
it is below.

**Verification caveat.** These reviews are static reads; the environment they
were written in has no macOS/Xcode toolchain. CI (`macos-14`, Xcode 16.2)
builds and runs the unit tests on every PR, but nothing here has been watched
running. Anything needing a live GUI session says so.

---

## Important

### P1 — The keystroke path still snapshots every running application

performance — important

`beginSession` → `appList(for:)` → `NSWorkspace.runningApplications` with an
`NSImage` per app and an MRU sort, all synchronous inside the event-tap
callback on every ⌘-Tab press. The scoped-display window-server queries (the
worst part) are cached since PR #54; the `NSWorkspace` snapshot and icon
resolution remain on the tap path, and a ⌘-Tab burst repeats them per press.
Individually 1–5 ms; together on a busy machine they approach the event-tap
deadline — the failure mode PR #17 survives rather than prevents. The 150 ms
show-delay hides the visual cost, not the tap cost.

Suggested fix: pre-warm the app list on `didActivateApplication` instead of at
keystroke time, and reuse the last snapshot within a short TTL (the PR #54
cache shape).

## Nice-to-have

### B10 — An update alert can appear on top of a live switch session

bugs — nice-to-have

`UpdateChecker.performCheck` can run `NSAlert.runModal()` while a ⌘-Tab
session is up (the launch check, plus any daily tick that coincides). The tap
is registered in `.commonModes`, so ⌘-Tab keeps starting sessions under a
modal run loop and keys are swallowed against a spinning alert.

Suggested fix: a "defer while switching" predicate injected from
`AppDelegate`; the reverse direction (`zapIsShowingAWindow`) already exists in
`SwitcherController`.

### Real-window thresholds disagree inside one feature area

bugs — nice-to-have

`WindowEnumerator.isDocumentSized` counts windows ≥120×120 while
`ScreenWindowScoper.minWindowSide` is 80: a 100×100 window counts toward
display scoping but is dropped from the off-Space window list.

Suggested fix: one shared constant, with a comment on why it has its value.

### `runningApplication(for:)` can resolve the wrong instance

bugs — nice-to-have

`AppListProvider.runningApplication(for:)` falls back to `byBundle.first` when
the pid lookup fails; with two instances of one bundle id (site-specific
browser wrappers, a relaunched app) quit/hide/open-files can reach the wrong
process.

Suggested fix: drop the bundle-only fallback and fail explicitly; the
`NSRunningApplication(processIdentifier:)` initializer already covers the
legitimate case.

### P3 — The whole overlay body re-evaluates on every selection change

performance — nice-to-have

`AGENTS.md` states the invariant — "only move the selection highlight on Tab,
do not rebuild the whole view" — but `selectedIndex` is `@Published` on the
same object as everything else, so `OverlayView.body` re-runs entirely per Tab
press, re-creating each icon's `dropDestination`, `onTapGesture`, `onHover`,
the gradient `GeometryReader` and the CRT canvas. SwiftUI absorbs it at ~10
icons; at 40 with large icons it's measurable.

Suggested fix: an `Equatable` icon-cell view taking `isSelected: Bool` so
unchanged cells skip re-evaluation.

### P6 — The appearance preview rebuilds its model on every body evaluation

performance — nice-to-have

`AppearanceView.preview` builds a fresh `OverlayModel` in a computed
property, so the live preview can hold no state and re-allocates per slider
tick. A `@StateObject` fixes it.

### P7 — PermissionsView polls two system APIs every second while open

performance — nice-to-have

`AXIsProcessTrusted()` + `CGPreflightScreenCaptureAccess()` on a 1 Hz Combine
timer that runs whenever the tab exists in the `TabView`, not only when
visible.

Suggested fix: 2–3 s interval, or start/stop on appear/disappear.

### V1 — The panel appears instantly, with no transition

visual and layout — nice-to-have

`orderFrontRegardless()` and it is simply there; the native switcher fades in
over ~80 ms. A short opacity fade (plus a 0.97→1.0 scale) would make Zap feel
materially more finished. The animation must start only once
`layout(keepTop:)` has committed a real size, or it re-introduces the
small-square flash the retry path prevents. Wants a live session to tune.

### V2 — The selected icon gets a highlight rect and nothing else

visual and layout — nice-to-have

A subtle scale (1.0 → 1.06) or soft glow would read faster at a glance,
especially with `highlightOpacity` turned down. Pairs with V1.

### V3 — Window preview tiles letterbox awkwardly

visual and layout — nice-to-have

Cells are a fixed 120×72 and thumbnails are `.fit`, so a portrait or
ultrawide window sits in a mostly-empty tile. Filling the tile (`.fill` +
clip, top-anchored) would read better: window previews are recognised by
their top-left chrome, not their aspect ratio.

### V4 — No window title anywhere when a window is focused

visual and layout — nice-to-have

The header shows the *app* name even while the selection is a window. Showing
the focused window's title there (or "App · 3 windows") uses space that is
already reserved.

### V5 — The panel's fixed two-thirds-up placement isn't configurable

visual and layout — nice-to-have

`layout` hardcodes `visible.minY + visible.height * 2/3`. On a 27" display
that's noticeably above centre. A three-way preference (centre / two-thirds /
remember where I dragged it) is cheap and noticed daily.

### V6 — Long app names truncate to the icon row's width

visual and layout — nice-to-have

The name is framed at `panelContentWidth`, which with 3–4 apps is narrow, so
long names tail-truncate where the panel could simply be a little wider for
the label.

### U2 — First launch has no onboarding

usability — nice-to-have

The app installs a status item, maybe prompts for Accessibility, and that's
it. There is no "Zap is now handling ⌘-Tab, here's what it can do" moment —
and per the README's own troubleshooting, the Accessibility grant is the
single most common failure mode. PR #22's `?` footer covers in-session
discoverability; this is about the first thirty seconds.

### U3 — The fallback mode can't be cancelled

usability — nice-to-have

With the Carbon ⌥-Tab hotkey there is no key-up detection, so Esc never
arrives and the 0.8 s auto-commit timer always fires. Inherent to the
mechanism; at minimum say so in the Settings caption, or let a second ⌥-Tab
onto the current app act as a cancel.

### U5 — Exclusions can only be set for running apps

usability — nice-to-have

`ExclusionsView` lists running apps plus already-excluded ones, so you cannot
pre-exclude an app that isn't running — which is exactly when you'd want to.
An "Add App…" button with an `NSOpenPanel` scoped to `/Applications` closes
this.

### U6 — No pinned / favourite apps

usability — nice-to-have

MRU is the right default, but two or three anchors at fixed indices make
muscle memory ("⌘-Tab, 3") work. The most-requested feature in every
third-party switcher. Design decision first, code second.

### U7 — Nothing indicates why an app is missing from a scoped display

usability — nice-to-have

Per-display scoping silently drops apps; a user who forgot the setting sees a
mysteriously short switcher. A small "this display only" marker on the panel
when a scope is in effect would explain it.

### U8 — Session app list is a snapshot

usability — nice-to-have

Apps launched or quit outside Zap's own ⌘Q path aren't reflected until the
next session. A deliberate trade-off for a stable hot path; commit safely
no-ops on a vanished app. Listed so it isn't rediscovered as a bug.

### F1 — Window-count badge on icons

missing features — nice-to-have

The hidden-app half shipped in PR #20. A per-app window count is the natural
companion and needs a cheap source: the Quartz window list already enumerated
for per-display scoping can provide it without extra AX calls.

### F2 — Configurable trigger hotkey

missing features — nice-to-have

⌘-Tab and the ⌥-Tab fallback are both hardwired; power users want ⌥-Space or
a hyper key. Needs a key-recorder control in Settings and a generalized
modifier match in the tap.

### F4 — Nothing built on the switch counter

missing features — nice-to-have

`Preferences` already counts switches (today and all-time) and About shows
the bare numbers. A "most-switched apps" view, or milestone moments (see D7),
is free delight from data already on disk.

### F5 — No localization

missing features — nice-to-have

Every string is a hardcoded English literal. SwiftUI's `Text` takes
`LocalizedStringKey` for free, so the app is structurally ready; there's just
no `.strings` catalog. Worth doing before this is shared widely.

### Window previews are one-shot stills

missing features — nice-to-have

Thumbnails are captured at reveal time (cache TTL 5 s, but nothing
re-captures while the list stays up), so a tile can show a stale view of a
window that changed on screen. A refresh on re-dwell, or periodic re-capture
of the selected tile only, keeps previews honest.

### A3 — No contrast floor

accessibility — nice-to-have

`labelColorHex` defaults to white on a 55%-opacity dark blur. Over a bright
wallpaper with low background opacity the app name can become hard to read,
and nothing handles `accessibilityDisplayShouldIncreaseContrast` (Reduce
Transparency and Reduce Motion are honoured since PR #23).

Suggested fix: honour increase-contrast the same way (raise background
opacity / stroke the label), or check a minimum contrast ratio.

### C1 — `SwitcherController` is ~1,200 lines doing five jobs

code quality — nice-to-have

Input routing, session state, type-to-search, quit/hide lifecycle, window
list, thumbnails, screen scoping. The pure bits are extracted well (which is
why the tests are good), but the *stateful* session machine — `isSessionActive`,
`selectedIndex`, `typeBuffer`, `pendingShortcut`, `quittingPIDs`,
`windowSelectedIndex` — wants to be a `SwitcherSession` value type with
explicit transitions. That's also the unlock for C2.

### C2 — Test coverage stops exactly where the risk starts

code quality — nice-to-have

Three dozen test files, all pure logic. Nothing covers session lifecycle,
commit/cancel, quit verification, hold-vs-tap, or dwell sequencing, because
they're welded to AppKit and `Timer`. Extracting the session machine (C1) plus
a fake clock would make all of it testable. Specific gaps carried forward:
reverse-cycling, commit/cancel, launch-at-login (needs an injectable
`SMAppService` seam), the fallback-hotkey preference path, and the timer/
callback wiring behind the stranded-session rule (the rule is tested; the
path is not).

### C4 — `Preferences` is a 500-line object with ~30 hand-written `didSet` writers

code quality — nice-to-have

It works and reads fine, but a small `@Stored` property wrapper would remove
~120 lines and make it impossible to forget a key. Worth doing only when it's
being touched anyway.

### C6 — `AppInfo.id` is `bundleID:pid` while MRU keys on bundle path

code quality — nice-to-have

Deliberate and correct (see `ISSUES.md` High #6), but the asymmetry deserves a
note at the `MRUTracker` type level, since it's the kind of thing a future
change "fixes" by accident.

### C7 — Unit tests host the real app binary

code quality — nice-to-have

The `isRunningTests` guard (now one definition, PR #60) keeps global hooks
from being installed; a separate pure-logic test bundle would remove the need
for the guard entirely.

## Delight backlog

Ordered by charm-per-line-of-code. D1 (the `?` hints footer) shipped in PR #22.

### D2 — Number badges on hold

delight — nice-to-have

After the switcher has been up ~600 ms without input, fade a tiny 1–9 badge
into each icon's corner. Teaches the number-jump shortcut passively and looks
like a heads-up display. No new key handling.

### D3 — Panel tint sampled from the selected app's icon

delight — nice-to-have

Pull the dominant colour from the highlighted icon and let the highlight (or a
subtle background wash) drift toward it as the selection moves. Needs a
per-bundle-ID colour cache so it costs nothing on the hot path.

### D4 — Googly eyes that track the highlight

delight — nice-to-have

Two xeyes in the corner whose pupils follow the selected icon. The only
decoration needing model wiring (the selection index) rather than just
preferences, and the one people would screenshot.

### D5 — "Surprise me" decoration

delight — nice-to-have

A meta-style that picks a random decoration per session. Zero drawing code.

### D6 — Boing-ball physics on idle

delight — nice-to-have

Leave the switcher open a few seconds with the Amiga decoration on and let the
ball actually *boing*: drop, bounce off the panel's bottom edge, rotate. The
raster machinery exists; it needs a display link and a sine.

### D7 — Switch-count milestones

delight — nice-to-have

A one-off, tasteful notification at 1,000 / 10,000 / 100,000 switches. Free,
from data already on disk (see F4).

### D8 — A "zap" sound, off by default

delight — nice-to-have

A 40 ms retro blip on commit. Ridiculous, opt-in, and exactly what a personal
app is allowed to have.

### D9 — Konami code

delight — nice-to-have

↑↑↓↓←→←→ then B, A while the switcher is open flips the panel to the Amiga
theme with the boing ball for the rest of the session. All the input plumbing
exists.

### D10 — Drag an icon out of the panel to pin it

delight — nice-to-have

If pinning (U6) happens, dragging an icon to reorder — with the pinned region
visually separated — is the natural interaction, and the drop machinery is
already wired for files.

### Right-click an icon for a quick menu

delight — nice-to-have

A context menu mid-switch: Quit, Hide, Exclude from switcher, (later) Pin.
One `.contextMenu`, all the actions exist (`quitSelected`, `hideSelected`,
`setExcluded`), and it makes the deep key vocabulary discoverable for
mouse-first users.

### Momentum scrolling for the icon row

delight — nice-to-have

The row scroll is direct-tracking with no inertia; a decaying momentum on
wheel flings (with the edge fade riding along) would feel like a native
scroller. Needs a display link or a few decay ticks; must respect Reduce
Motion.

### Selection echo

delight — nice-to-have

The previous highlight fades out over ~150 ms behind the new one (a ghost
rect at the old index), giving fast Tab-bursts a visible trail so the eye can
follow where the highlight went. One extra rect keyed to the previous index.

### Peek-on-hold

delight — nice-to-have

Dwell longer than the window-list delay on one app and its selected-window
preview grows to a large thumbnail (or fades the rest of the panel). The
capture machinery already exists; this is layout only.

### Decoration ideas

delight — nice-to-have

`DecorationKind` currently knows `stripes` and `ball`; several of these want
new kinds — `background`, `border`, edge strip, pixel `sprite` — and the
sprite family can reuse the raster machinery `BoingBallDecoration` already
has (fixed-resolution bitmap, nearest-neighbour upscale, cached `CGImage`).
Like the existing ZX/Apple/Amiga styles, most are affectionate nods to
trademarked designs — the same homage spirit, and the same bucket.

**Companions to existing styles**
- **Boing grid** — the original demo's magenta wireframe grid, faint behind
  the whole panel, so the Amiga preset becomes a full diorama. (Background.)
- **Synthwave sun** — a striped setting-sun semicircle in a corner; the
  natural partner for Vaporwave stripes + CRT mode.
- **Spectrum loading border** — alternating cyan/yellow bars around the
  panel's edge, the tape-loading screen every 80s kid stared at. (Border.)

**Pixel sprites** (data-driven bitmaps over the boing-ball raster path)
- **Tetromino stack** — a few classic pieces snugged into the top corner as if
  mid-fall. Blocks stacking into a corner is exactly what tetrominoes do; the
  strongest candidate of the lot.
- **Space invader** — the 11×8 alien, crisp chunky pixels in the corner.
- **Clarus the dogcow** — Susan Kare deep cut for the Mac faithful. Moof.

**More machine homages**
- **C64** — dark-blue panel with the boot screen's lighter-blue inner border;
  optionally a tiny `READY.` with a blinking block cursor.
- **Atari woodgrain** — a 2600-style woodgrain strip along the panel's bottom
  edge. Ridiculous in the best way.
- **Classic Mac title bar** — the System 7 six-pinstripe title bar with a
  close box across the panel top; makes the switcher read as a vintage window.
- **IBM stripes** — the eight-bar blue monogram stack in a corner.

## Known limitations (not bugs — don't re-file)

- **Cold-launch MRU order.** There is no public API for the system's own MRU
  order. Zap seeds from the previous session's persisted order and
  self-corrects after the first few switches. (`ISSUES.md` High #3, `PLAN.md`.)
- **Full-screen windows on other Spaces.** macOS won't let Zap switch to
  another Space directly; choosing such a window activates its app and lets
  the system decide. Their titles are also blank without Screen Recording. Off
  by default and explained in the Settings caption.
- **Private SPI.** `_AXUIElementGetWindow` and the SkyLight `CGS*` symbols are
  fine for Developer ID + notarization but would block App Store submission.
  Both are best-effort with `nil` fallbacks (now also documented in the
  README, PR #65).
- **Signing.** No development team is set on purpose; contributors configure
  their own. This is why a debug build re-prompts for Accessibility on every
  rebuild (README troubleshooting).
