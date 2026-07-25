# Zap — Analysis & Backlog

The living record of what's wrong, what's missing, and what would be fun — the
document future work starts from. Entries are removed as they ship.

**Provenance.** This consolidates the July 2026 full review (`claude-review.md`,
now merged here) with everything still open from the earlier `awesome.md` review
(which this file replaces). `ISSUES.md` stays as the archived June 2026
review-and-resolution log; nothing still open from it was dropped — the survivors
are folded in below.

**Verification caveat.** These reviews are static reads: the environment they were
written in has no macOS/Xcode toolchain. CI (`macos-14`, Xcode 16.2) builds and
runs the unit tests on every PR, but nothing here has been watched running. Each
entry carries a confidence, and anything needing a live GUI session says so.

Legend: **Sev** = user impact if hit · **Conf** = confidence the finding is real ·
**Eff** = implementation effort (XS/S/M/L).

---

## 0. In flight

Open PRs from the July 2026 pass. These leave the backlog when they merge; they
are listed here so nothing is lost if one is closed instead.

| PR | Entry | What it does |
|----|-------|--------------|
| [#16](https://github.com/L-K-M/Zap/pull/16) | B1 | Hover no longer takes the selection until the pointer actually moves |
| [#17](https://github.com/L-K-M/Zap/pull/17) | B2 | Watchdog recovers a session stranded by a disabled event tap |
| [#18](https://github.com/L-K-M/Zap/pull/18) | B3 | 250 ms AX messaging timeout, so a hung app can't freeze the switcher |
| [#19](https://github.com/L-K-M/Zap/pull/19) | B4 | Q/H/W matched by character, fixing non-QWERTY layouts |
| [#20](https://github.com/L-K-M/Zap/pull/20) | F1 (partial) | Hidden apps are faded and badged; ⌘H updates the row immediately |
| [#21](https://github.com/L-K-M/Zap/pull/21) | F3, B5 | Subsequence matching ("vsc" → Visual Studio Code) + no-match badge state |
| [#22](https://github.com/L-K-M/Zap/pull/22) | D1, U1 | `?` toggles a contextual key-hints footer |
| [#23](https://github.com/L-K-M/Zap/pull/23) | A1, A2 | Reduce Transparency / Reduce Motion honoured; icons labelled |

Each wants a manual pass on a real machine before it's trusted — the unit tests
cover the pure rules, not the AppKit behavior around them.

---

## 1. Bugs

### B6 — Apps whose name starts with a digit are unreachable by typing
**Sev: low · Conf: high · Eff: S**

`handleTypedCharacter` (`SwitcherController.swift`) treats *any* leading 1–9 as a
number-key jump, so "1Password" (and "1Blocker", "3CX", "4K Video Downloader")
can never be typed: the first keystroke commits to whatever app is Nth in the
list — a destructive switch, not a preview.

Least-surprising fix: only treat a digit as a jump when no visible app name
starts with that digit. Alternatives: require the jump within a short window of
the session opening, or make it a preference.

### B7 — The search badge's height isn't reserved in the window-list budget
**Sev: low · Conf: medium-high · Eff: XS**

`windowListBudget` subtracts `headerHeight + dividerReserve` from
`maxPanelHeight`, and `headerHeight` covers only padding + name + icon row. The
search badge (≈26 pt plus a 10 pt stack gap) is unaccounted for. Type a query
while a long window list is open on a short screen and the panel overflows its
budget; the frame clamp in `layout` then shifts the panel *up*, moving the icon
row — the exact jump the fixed-top-edge design exists to prevent.

(PR #22 adds the same reservation for its hints footer; the badge still needs
one.)

### B8 — Pending-quit state doesn't survive into the next session
**Sev: low · Conf: high · Eff: S**

`endSession` clears `quittingPIDs` but leaves the `pendingQuits` verification
timers running. Start a new session inside the 2 s window and the app you just
asked to quit is drawn undimmed and selectable again; `verifyQuit` then acts on
the *new* session, potentially removing a row the user is looking at. Not
harmful, but it's the one piece of this otherwise careful state machine that
isn't session-scoped.

### B9 — Vertical scrolling does nothing while a short window list is showing
**Sev: low · Conf: medium · Eff: XS**

`handleScroll` hands *all* vertical gestures to the window list whenever
`model.windows` is non-empty, but the window section only becomes a `ScrollView`
once it exceeds `windowListBudget`. With a short list, a vertical wheel scroll is
consumed by nothing — the icon row, which may well be overflowing, refuses to
move. Only "windows shown **and** actually scrollable" should divert the gesture.

### B10 — An update alert can appear on top of a live switch session
**Sev: low · Conf: high · Eff: S** *(carried from `awesome.md §1.2`)*

`UpdateChecker.performCheck` can run `NSAlert.runModal()` while a ⌘-Tab session
is up; the tap keeps swallowing keys under a spinning modal run loop. Rare (the
launch check only), and the fix is a "defer while switching" predicate injected
from `AppDelegate`.

---

## 2. Performance & responsiveness

### P1 — Everything expensive happens on the main thread, on the keystroke path
**Conf: high**

`beginSession` → `appList(for:)` → `NSWorkspace.runningApplications` (+ an
`NSImage` per app) → `MRUTracker.ordered` → and, when a display is scoped,
`CGWindowListCopyWindowInfo(.optionAll)` over every window on every Space plus
two SkyLight `CGSCopyWindowsWithOptionsAndTags` queries — all synchronous, all
inside the event-tap callback.

Individually 1–5 ms; together, on a busy machine with 60+ windows, they are how a
tap callback gets close to the event-tap deadline (which is what B2/PR #17 exists
to survive). The 150 ms show-delay hides the *visual* cost, not the *tap* cost —
the work runs before the delay, not during it.

Ideas: cache the scoped PID set for ~250 ms (a ⌘-Tab burst re-queries it on every
press today); pre-warm the app list on `didActivateApplication` rather than at
keystroke time; skip the scoping queries entirely when the target screen's stored
mode is `.off`.

### P2 — Thumbnails are captured strictly sequentially
**Conf: high · Eff: S**

`loadThumbnails` awaits each capture in a `for` loop: nine windows × ~40–80 ms ≈
half a second before the last tile fills in. The shareable-content snapshot is
already shared across the batch, so a bounded `TaskGroup` (3–4 at a time) would
cut wall time without hammering the compositor. Capture the *selected* window
first.

### P3 — The whole overlay body re-evaluates on every selection change
**Conf: medium-high**

`AGENTS.md` states the invariant — "only move the selection highlight on Tab, do
not rebuild the whole view" — but `selectedIndex` is `@Published` on the same
object as `apps`, `windows`, `scrollOffset` and `typeQuery`, so `OverlayView.body`
re-runs entirely for every Tab press, re-creating each icon's `dropDestination`,
`onTapGesture`, `onHover` and the gradient `GeometryReader`. SwiftUI absorbs it at
~10 icons; at 40 icons with a large icon size it's measurable. Splitting the icon
cell into its own `Equatable` `View` (taking `isSelected` as a plain `Bool`)
restores the intent.

### P4 — `Preferences.dayStamp` builds a `DateFormatter` on every switch
**Conf: high · Eff: XS**

`recordSwitch` runs on *every commit*, on the main thread, right as the app is
being activated, and allocates one of Foundation's genuinely expensive objects.
`Calendar.current.dateComponents` + `String(format:)` is ~100× cheaper and
sidesteps the stale-timezone problem a cached formatter would introduce.

### P5 — MRU order is rewritten to `UserDefaults` on every system-wide activation
**Conf: high · Eff: XS**

`AppListProvider.observeActivations` calls `persistMRU()` — a 50-element array
write — on *every* app activation anywhere in the system, not just Zap's own
switches. Debounce, or persist every Nth change plus on terminate.

### P6 — `AppearanceView.preview` rebuilds its `OverlayModel` on every body eval
**Conf: high · Eff: XS** *(carried from `awesome.md §2.2`)* — a `@StateObject`
fixes it. Harmless today, but it means the live preview can't hold any state.

### P7 — `PermissionsView` polls two system APIs every second while open
**Conf: high · Eff: XS** — `AXIsProcessTrusted()` + `CGPreflightScreenCaptureAccess()`
on a 1 Hz timer that runs whenever the tab exists in the `TabView`, not only when
it's visible. A 2–3 s interval, or start/stop on appear/disappear.

---

## 3. Visual & layout

### V1 — The panel appears instantly, with no transition
**Conf: high · Eff: S**

`orderFrontRegardless()` and it's simply *there*; the native switcher fades in
over ~80 ms. A short opacity fade (plus a 0.97→1.0 scale) would make Zap feel
materially more finished. The catch: the animation must start only once
`layout(keepTop:)` has committed a real size, or it re-introduces the "small
square" flash the retry path exists to prevent. Wants a live session to tune.

### V2 — The selected icon gets a highlight rect and nothing else
**Conf: medium** — a subtle scale (1.0 → 1.06) or soft glow would read faster at a
glance, especially with `highlightOpacity` turned down. Pairs with V1.

### V3 — Window preview tiles letterbox awkwardly
**Conf: medium** — cells are a fixed 120×72 and thumbnails are `.fit`, so a
portrait or ultrawide window sits in a mostly-empty tile. Filling the tile
(`.fill` + clip, top-centre anchored) would read better: window previews are
recognised by their top-left chrome, not their aspect ratio.

### V4 — No window title anywhere when the app row is focused
**Conf: high** — the header shows the *app* name even while the selection is a
window. Showing the focused window's title there (or "App · 3 windows") uses
space that's already reserved.

### V5 — The panel's fixed two-thirds-up placement isn't configurable
**Conf: high · Eff: S** — `layout` hardcodes `visible.minY + visible.height * 2/3`.
On a 27" display that's noticeably above centre. A three-way preference (centre /
two-thirds / remember where I dragged it) is cheap and noticed daily.

### V6 — Long app names truncate to the icon row's width
**Conf: medium** — the name is framed at `panelContentWidth`, which with 3–4 apps
is narrow, so "Microsoft Remote Desktop Connection Client" tail-truncates where
the panel could simply be a little wider for the label.

---

## 4. UX & interaction

### U2 — First launch has no onboarding
**Conf: high** — the app installs a status item, maybe prompts for Accessibility,
and that's it. There's no "Zap is now handling ⌘-Tab, here's what it can do"
moment — and per the README's own troubleshooting section, the Accessibility
grant is the single most common failure mode. (PR #22's `?` footer covers
in-session discoverability; this is about the first thirty seconds.)

### U3 — The fallback mode can't be cancelled
**Conf: high** *(carried from `awesome.md §2.1`)* — with the Carbon ⌥-Tab hotkey
there's no key-up detection, so Esc never arrives and the auto-commit timer
always fires. Inherent to the mechanism; at minimum say so in the Settings
caption, or let a second ⌥-Tab onto the current app act as a cancel.

### U4 — Secure Input silently disables the whole app
**Conf: high · Eff: S** — while any app has secure event input enabled (a focused
password field, some terminals, password managers), CGEventTaps receive no key
events and ⌘-Tab falls through to the *native* switcher with no explanation.
`IsSecureEventInputEnabled()` detects it; surfacing it in the Permissions tab (and
dimming the menu-bar icon, as Pause already does) turns a baffling intermittent
failure into a legible one.

### U5 — Exclusions can only be set for *running* apps
**Conf: high** — `ExclusionsView` lists running apps plus already-excluded ones, so
you cannot pre-exclude an app that isn't running — which is exactly when you'd
want to. An "Add App…" button with an `NSOpenPanel` scoped to `/Applications`
closes this.

### U6 — No pinned / favourite apps
**Conf: medium** — MRU is the right default, but two or three anchors at fixed
indices make muscle memory ("⌘-Tab, 3") work. The most-requested feature in every
third-party switcher. Design decision first, code second.

### U7 — Nothing indicates *why* an app is missing from a scoped display
**Conf: medium** — per-display scoping silently drops apps; a user who forgot the
setting sees a mysteriously short switcher. A small "this display only" marker on
the panel when a scope is in effect would explain it.

### U8 — Session app list is a snapshot
**Conf: high** *(carried from `awesome.md §2.3` / `ISSUES.md` Medium #9)* — apps
launched or quit outside Zap's own ⌘Q path aren't reflected until the next
session. A deliberate trade-off for a stable hot path; commit safely no-ops on a
vanished app. Listed so it isn't rediscovered as a bug.

---

## 5. Missing features

### F1 — Window-count badge on icons
**Conf: high · Eff: S** — the hidden-app half ships in PR #20. A per-app window
count is the natural companion and needs a cheap source: the Quartz window list
already enumerated for per-display scoping can provide it without extra AX calls.

### F2 — Configurable trigger hotkey
**Conf: high · Eff: M** *(carried from `awesome.md §3.2`)* — ⌘-Tab and the ⌥-Tab
fallback are both hardwired; power users want ⌥-Space or a hyper-key. Needs a
key-recorder control in Settings.

### F4 — Nothing built on the switch counter
**Conf: medium** — `Preferences` already counts switches (today and all-time) and
About shows the bare numbers. A "most-switched apps" view, or milestone moments
(see D7), is free delight from data already on disk.

### F5 — No localization
**Conf: high** — every string is a hardcoded English literal. SwiftUI's `Text`
takes `LocalizedStringKey` for free, so the app is structurally ready; there's
just no `.strings` catalog. Worth doing before this is shared widely.

---

## 6. Accessibility

*(A1 Reduce Transparency / Reduce Motion and A2 icon labels ship in PR #23.)*

### A3 — No contrast floor
**Conf: medium** — `labelColorHex` defaults to white on a 55%-opacity dark blur.
Over a bright wallpaper with low background opacity the app name can become hard
to read, and nothing handles
`accessibilityDisplayShouldIncreaseContrast`. A minimum-contrast check on the
label colour (or honouring increase-contrast the way PR #23 honours the other
two) would close it.

---

## 7. Code quality, architecture, tests

### C1 — `SwitcherController` is ~1,000 lines doing five jobs
**Conf: high** — input routing, session state, type-to-search, quit/hide
lifecycle, window list, thumbnails, screen scoping. The pure bits are extracted
well (which is why the tests are good), but the *stateful* session machine —
`isSessionActive`, `selectedIndex`, `typeBuffer`, `pendingShortcut`,
`quittingPIDs`, `windowSelectedIndex` — wants to be a `SwitcherSession` value type
with explicit transitions. That's also the unlock for C2. *(Extends
`awesome.md`'s "split pure session logic out" and `ISSUES.md` Improvement #2.)*

### C2 — Test coverage stops exactly where the risk starts
**Conf: high** — two dozen test files, all pure logic. Nothing covers session lifecycle,
commit/cancel, quit verification, hold-vs-tap, or hover, because they're welded
to AppKit and to `Timer`. Extracting the session machine (C1) plus a fake clock
would make all of it testable. Specific gaps carried forward: reverse-cycling,
commit/cancel, launch-at-login (needs an injectable `SMAppService` seam), the
fallback-hotkey preference path, and the stranded-session wiring added in PR #17
(the rule is tested; the timer/callback path is not).

### C3 — Two identical `isRunningTests` implementations
**Conf: high · Eff: XS** — `AppDelegate` and `UpdateChecker` each define it.

### C4 — `Preferences` is a 466-line object with ~30 hand-written `didSet` writers
**Conf: medium** — it works and reads fine, but a small `@Stored` property wrapper
would remove ~120 lines and make it impossible to forget a key. Worth doing only
when it's being touched anyway.

### C5 — Private SPI use isn't mentioned in the README
**Conf: high · Eff: XS** — `_AXUIElementGetWindow` and the SkyLight `CGS*` symbols
are correctly best-effort with `nil` fallbacks and the trade-off is explained in
the source, but not where someone evaluating a system-level tool would look. One
sentence.

### C6 — `AppInfo.id` is `bundleID:pid` while MRU keys on bundle ID alone
**Conf: high** — deliberate and correct (see `ISSUES.md` High #6), but the
asymmetry deserves a note at the `MRUTracker` type level, since it's the kind of
thing a future change "fixes" by accident.

### C7 — Unit tests host the real app binary
**Conf: high** *(carried from `ISSUES.md` Tests #6)* — the `isRunningTests` guard
keeps global hooks from being installed; a separate pure-logic test bundle would
remove the need for the guard entirely.

---

## 8. Delight backlog

Ordered by charm-per-line-of-code. *(D1, the `?` hints footer, ships in PR #22.)*

### D2 — Number badges on hold
After the switcher has been up ~600 ms without input, fade a tiny 1–9 badge into
each icon's corner. Teaches the number-jump shortcut passively and looks like a
heads-up display. No new key handling.

### D3 — Panel tint sampled from the selected app's icon
Pull the dominant colour from the highlighted icon and let the highlight (or a
subtle background wash) drift toward it as the selection moves. Makes the panel
feel alive and app-aware; needs a per-bundle-ID colour cache so it costs nothing
on the hot path.

### D4 — Googly eyes that track the highlight
Two xeyes in the corner whose pupils follow the selected icon. The only
decoration needing model wiring (the selection index) rather than just
preferences, and the one people would screenshot. *(From `awesome.md §4.4`.)*

### D5 — "Surprise me" decoration
A meta-style that picks a random decoration per session. Zero drawing code.

### D6 — Boing-ball physics on idle
Leave the switcher open a few seconds with the Amiga decoration on and let the
ball actually *boing* — drop, bounce off the panel's bottom edge, rotate. The
raster machinery exists; it needs a display link and a sine.

### D7 — Switch-count milestones
A one-off, tasteful notification at 1,000 / 10,000 / 100,000 switches. Free, from
data already on disk (see F4).

### D8 — A "zap" sound, off by default
A 40 ms retro blip on commit. Ridiculous, opt-in, and exactly what a personal app
is allowed to have.

### D9 — Konami code
↑↑↓↓←→←→ then B, A while the switcher is open flips the panel to the Amiga theme
with the boing ball for the rest of the session. All the input plumbing exists.

### D10 — Drag an icon out of the panel to pin it
If pinning (U6) happens, dragging an icon to reorder — with the pinned region
visually separated — is the natural interaction, and the drop machinery is
already wired for files.

### Decoration ideas *(carried verbatim in spirit from `awesome.md §4`)*

`DecorationKind` currently knows `stripes` and `ball`; several of these want new
kinds — `background`, `border`, edge strip, pixel `sprite` — and the sprite family
can reuse the raster machinery `BoingBallDecoration` already has (fixed-resolution
bitmap, nearest-neighbour upscale, cached `CGImage`). Like the existing
ZX/Apple/Amiga styles, most are affectionate nods to trademarked designs — the
same homage spirit, and the same bucket.

**Companions to existing styles**
- **Boing grid** — the original demo's magenta wireframe grid, faint behind the
  whole panel, so the Amiga preset becomes a full diorama. (Background kind.)
- **Synthwave sun** — a striped setting-sun semicircle in a corner; the natural
  partner for Vaporwave stripes + CRT mode.
- **Spectrum loading border** — alternating cyan/yellow bars around the panel's
  edge, the tape-loading screen every 80s kid stared at. (Border kind.)

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
- **Classic Mac title bar** — the System 7 six-pinstripe title bar with a close
  box across the panel top; makes the switcher read as a vintage window.
- **IBM stripes** — the eight-bar blue monogram stack in a corner.

---

## 9. Known limitations (not bugs — don't re-file)

- **Cold-launch MRU order.** There is no public API for the system's own MRU
  order. Zap seeds from the previous session's persisted order and self-corrects
  after the first few switches. (`ISSUES.md` High #3, `PLAN.md`.)
- **Full-screen windows on other Spaces.** macOS won't let Zap switch to another
  Space directly; choosing such a window activates its app and lets the system
  decide. Their titles are also blank without Screen Recording. Off by default
  and explained in the Settings caption.
- **Private SPI.** `_AXUIElementGetWindow` and the SkyLight `CGS*` symbols are
  fine for Developer ID + notarization but would block App Store submission.
  Both are best-effort with `nil` fallbacks (see C5).
- **Signing.** No development team is set on purpose; contributors configure
  their own. This is why a debug build re-prompts for Accessibility on every
  rebuild (README troubleshooting).
