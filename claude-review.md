# Zap — Full Project Review (July 2026)

> **Filename note.** This review was requested as `claude.md`. The repo already
> contains `CLAUDE.md` (the agent instructions), and macOS filesystems are
> case-insensitive by default — checking out both paths on a Mac makes them the
> *same file* and silently clobbers the instructions. It is therefore filed as
> `claude-review.md`. Its content is consolidated into `ANALYSIS.md` (the living
> backlog) at the end of this pass.

A fresh, end-to-end read of every source file (~5.4k lines of app code, ~1.9k
lines of tests), the docs (`PLAN.md`, `AGENTS.md`, `ISSUES.md`, `awesome.md`),
the build scripts and the CI workflows. Nothing here was verified by running the
app — there is no macOS/Xcode toolchain in this environment — so every claim is
from static reading, and each entry says how confident I am.

## Verdict first

The codebase is genuinely good. Modules are small and single-purpose, the hard
system-level parts (event tap re-enable, cooperative activation hand-off, the
"small square" layout retry, the SkyLight Space classification failing *open*)
are handled deliberately and, crucially, explained in comments that say *why*.
Pure logic is consistently extracted and unit-tested — `IconRowGeometry`,
`WindowGridGeometry`, `ScreenWindowScoper.pids`, `bestMatchIndex`,
`defaultSelection`, `maxPanelHeight`. That is a rare and valuable discipline for
an app this system-entangled.

The gaps are almost all at the *edges* of that discipline: the parts that can't
be unit-tested (live hover, a stalled event tap, a hung Accessibility client) and
the parts nobody has needed yet (non-QWERTY layouts, Reduce Transparency,
first-run guidance). The two most valuable findings below (B1, B2) are both
"what happens when the environment misbehaves" problems, and both are cheap to
fix.

Legend: **Sev** = user impact if hit · **Conf** = my confidence the finding is
real · **Eff** = implementation effort.

---

## 1. Bugs

### B1 — The pointer steals the selection when the panel appears under it
**Sev: high · Conf: high · Eff: S**

`OverlayView.swift:31-33` fires `onHoverApp` on any `onHover(true)`, and
`SwitcherController.hoverApp` (`SwitcherController.swift:728`) moves the
selection. The panel is presented on the screen *containing the pointer*
(`targetScreen()`, `SwitcherController.swift:931`) and horizontally centred about
two-thirds up. So if the cursor happens to be resting anywhere in that band —
a very common resting place — SwiftUI delivers a hover for the icon that appears
under it and the highlight jumps there **without the user moving the mouse**.

That silently breaks the single most important behavior in the app: ⌘-Tab-and-
release toggling the two most-recent apps. The user taps ⌘-Tab expecting their
previous app and gets whatever icon happened to materialise under a stationary
cursor. It also defeats `defaultSelection(...)`, which the project went to some
trouble to get right.

The native switcher has the same panel-under-cursor situation and does *not*
do this: hover only takes over after real pointer movement.

*Fix:* record `NSEvent.mouseLocation` when the panel is shown and ignore hover
callbacks until the pointer has actually moved more than a few points from that
origin. Pure and testable (`hoverShouldTakeOver(origin:current:threshold:)`).

### B2 — A stalled event tap can leave a session stuck, swallowing every keystroke
**Sev: high · Conf: high · Eff: S–M**

`EventTapMonitor.handle` correctly re-enables the tap on
`.tapDisabledByTimeout` / `.tapDisabledByUserInput` (`EventTapMonitor.swift:111-117`).
But events delivered *while the tap was disabled are gone*. The commit trigger
is exactly one such event: the `flagsChanged` that reports Command going up
(`EventTapMonitor.swift:133-136`).

Miss it and the session never ends. `isSessionActive` stays true, so:

- the overlay stays on screen forever,
- **every subsequent `keyDown` is consumed** (`EventTapMonitor.swift:194-201`
  swallows anything unrecognised while switching) — the keyboard appears dead
  to every app until the user finds the menu-bar item or clicks outside (and
  click-outside only helps if `closeOnClickOutside` is on).

The system disables a tap precisely when the callback was slow — and B3/P1 below
describe a realistic way to make it slow (a hung app's AX reply on the main
thread). These two compound: the hang causes the disable, the disable strands
the session, and the stranded session eats the keyboard.

*Fix:* two cheap belts.
1. On tap re-enable, if a session is live, reconcile against reality.
2. While a session is live in event-tap mode, run a low-frequency (~0.4 s)
   watchdog that reads the real modifier state
   (`CGEventSource.flagsState(.combinedSessionState)`) and commits when Command
   is no longer physically down. Only in event-tap mode — the ⌥-Tab fallback
   has no Command to watch.

### B3 — Window enumeration blocks the main thread on a hung app
**Sev: medium-high · Conf: high · Eff: XS**

`WindowEnumerator.windows(forPID:)` (`WindowEnumerator.swift:50`) walks
Accessibility attributes synchronously on the main thread, from the dwell timer.
`AXUIElementCopyAttributeValue` is a *synchronous IPC round-trip* to the target
process and uses the default messaging timeout when none is set — seconds, not
milliseconds. Dwell on a beachballing app and Zap's run loop stalls with it:
the panel freezes, and the event tap gets disabled by timeout (→ B2).

*Fix:* `AXUIElementSetMessagingTimeout(app, 0.25)` right after
`AXUIElementCreateApplication(pid)`. One line; the timeout propagates to the
element hierarchy of that app. (Moving enumeration off the main thread is the
fuller fix, but AX elements are best used from one thread and the timeout
removes the pathology.)

### B4 — Q / W / H are matched by key *position*, so they're the wrong keys on non-QWERTY layouts
**Sev: medium · Conf: high · Eff: S**

`KeyCode.q = 0x0C`, `.w = 0x0D`, `.h = 0x04` (`KeyCodes.swift:9-11`) are physical
positions. On AZERTY, position `0x0C` types `A`. So a French user holding ⌘-A
mid-switch **quits the highlighted app**, while ⌘-Q does nothing at all. Dvorak,
QWERTZ and Colemak all mis-map at least one of the three.

The ugly part is that the destructive action (quit) is the one that fires by
accident. Everything else in the same file already does this correctly: type-to-
search reads the character layout-aware via `typedCharacter(for:)`
(`EventTapMonitor.swift:235`).

*Fix:* route the three action keys through the same character translation.
Arrows / Escape / Delete / Tab stay position-based, which is correct for them.
(This was already noted in `awesome.md §1.1` and is still open.)

### B5 — The search badge never shows a "no match" state its own comment promises
**Sev: low · Conf: high · Eff: XS**

`OverlayView.swift:234-236` documents the badge as "Dims when nothing matches so
a typo is legible" — there is no such logic anywhere. `applyTypeQuery`
(`SwitcherController.swift:369`) deliberately leaves the selection put when
nothing matches, which is the right call, but the user gets *zero* feedback that
their query matched nothing: the highlight simply stops responding. Combined
with the fact that every keystroke is swallowed, a mistyped query feels like the
switcher has frozen.

*Fix:* carry a `matched` flag into the model and tint/dim the badge when false.

### B6 — Apps whose name starts with a digit are unreachable by typing
**Sev: low · Conf: high · Eff: S**

`handleTypedCharacter` (`SwitcherController.swift:345`) treats *any* leading
1–9 as a number-key jump. "1Password" (and "1Blocker", "3CX", "4K Video
Downloader") can therefore never be typed — the first keystroke commits to
whatever app happens to be Nth in the list, which is also a *destructive* switch,
not a preview.

*Fix options:* only treat a digit as a jump if no app name starts with that
digit; or require the jump digit to be pressed within a short window of the
session opening; or make the number-jump a preference. The first is the least
surprising.

### B7 — The search badge's height isn't reserved in the window-list budget
**Sev: low · Conf: medium-high · Eff: XS**

`windowListBudget` (`OverlayView.swift:462-468`) subtracts `headerHeight +
dividerReserve` from `maxPanelHeight`, and `headerHeight`
(`OverlayView.swift:198`) covers only padding + name + icon row. The search badge
(≈26 pt plus a 10 pt stack gap) is unaccounted for. Type a query while a long
window list is open on a short screen and the panel overflows its budget; the
frame clamp in `layout` then shifts the panel *up*, moving the icon row — the
exact jump the fixed-top-edge design exists to prevent.

### B8 — Pending-quit state doesn't survive into the next session
**Sev: low · Conf: high · Eff: S**

`endSession` clears `quittingPIDs` but leaves the `pendingQuits` verification
timers running (`SwitcherController.swift:608-621`). Start a new session inside
the 2 s window and the app you just asked to quit is drawn undimmed and is
selectable again — pressing Enter on it re-activates a process that's mid-quit.
`verifyQuit` then early-returns on the *new* session (it checks
`isSessionActive`, which is now true, and calls `removeApp`, which may remove an
app the user is currently looking at). Not harmful, but it's the one piece of
this otherwise careful state machine that isn't session-scoped.

### B9 — Vertical scrolling does nothing while a short window list is showing
**Sev: low · Conf: medium · Eff: XS**

`handleScroll` (`OverlayWindowController.swift:384-385`) hands *all* vertical
gestures to the window list whenever `!model.windows.isEmpty`. But the window
section only becomes a `ScrollView` when it exceeds `windowListBudget`
(`OverlayView.swift:280`). With a short list, a vertical wheel scroll is
consumed by nothing at all — the icon row, which may well be overflowing,
refuses to move. Only the *state* "windows shown and list actually scrollable"
should divert the gesture.

### B10 — An update alert can appear on top of a live switch session
**Sev: low · Conf: high · Eff: S**

Carried over from `awesome.md §1.2` and still true: `UpdateChecker.performCheck`
can run `NSAlert.runModal()` while a ⌘-Tab session is up. The tap keeps
swallowing keys under a spinning modal run loop. Rare (launch check only), but
the fix is a one-line "defer while switching" predicate injected from
`AppDelegate`.

---

## 2. Performance & responsiveness

### P1 — Everything expensive happens on the main thread, on the keystroke path
**Conf: high**

The whole hot path is synchronous main-thread work inside the event-tap
callback: `beginSession` → `appList(for:)` → `NSWorkspace.runningApplications`
(+ an `NSImage` per app) → `MRUTracker.ordered` → and, when a display is scoped,
`CGWindowListCopyWindowInfo(.optionAll)` over *every window on every Space* plus
two SkyLight `CGSCopyWindowsWithOptionsAndTags` queries
(`ScreenWindowScoper.swift:55`, `FullscreenSpaceWindows.swift:61`).

Individually these are 1–5 ms. Together, on a busy machine with 60+ windows,
they are the reason a tap could exceed the event-tap deadline (→ B2). The
150 ms show-delay hides the *visual* cost but not the *tap* cost — the work runs
before the delay, not during it.

*Ideas:* cache the scoped PID set for ~250 ms (a ⌘-Tab burst re-queries it every
press today); pre-warm the app list on `didActivateApplication` instead of at
keystroke time; skip the SkyLight query entirely when no display is scoped
(already done) *and* when the target screen's stored mode is `.off`.

### P2 — Thumbnails are captured strictly sequentially
**Conf: high · Eff: S**

`loadThumbnails` (`SwitcherController.swift:800-805`) awaits each capture in a
`for` loop. Nine windows × ~40-80 ms of `SCScreenshotManager` ≈ half a second
before the last tile fills in. The shareable-content snapshot is already shared
across the batch (nice), so a bounded `TaskGroup` (3–4 at a time) would cut wall
time without hammering the compositor. Capture the *selected* window first.

### P3 — The whole overlay body re-evaluates on every selection change
**Conf: medium-high**

`AGENTS.md` states the invariant: "only move the selection highlight on Tab, do
not rebuild the whole view." In practice `model.selectedIndex` is `@Published`
on the same object as `apps`, `windows`, `scrollOffset` and `typeQuery`, so
`OverlayView.body` re-runs entirely for every Tab press — re-creating each
icon's `dropDestination`, `onTapGesture`, `onHover` and the gradient
`GeometryReader`. SwiftUI's diffing absorbs it at ~10 icons; at 40 icons with a
large icon size it's measurable. Splitting the icon cell into its own
`Equatable` `View` (taking `isSelected` as a plain `Bool`) restores the intent.

### P4 — `Preferences.dayStamp` builds a `DateFormatter` on every switch
**Conf: high · Eff: XS**

`Preferences.swift:415-421` allocates and configures a `DateFormatter` (one of
Foundation's genuinely expensive objects) inside `recordSwitch`, which runs on
*every commit*, on the main thread, right as the app is being activated.
`Calendar.current.dateComponents` + `String(format:)` is ~100× cheaper and
sidesteps the stale-timezone problem a cached formatter would introduce.

### P5 — MRU order is rewritten to `UserDefaults` on every system-wide activation
**Conf: high · Eff: XS**

`AppListProvider.observeActivations` (`AppListProvider.swift:113`) calls
`persistMRU()` — a 50-element array write — on *every* app activation anywhere in
the system, not just Zap's own switches. Coalescing (debounce, or persist on
`applicationWillTerminate` + every Nth change) removes pointless disk churn.

### P6 — `AppearanceView.preview` rebuilds its `OverlayModel` on every body eval
**Conf: high · Eff: XS** — carried from `awesome.md §2.2`; a `@StateObject`
fixes it. Harmless today, but it means the live preview can't hold any state.

### P7 — `PermissionsView` polls two system APIs every second while open
**Conf: high · Eff: XS** — `AXIsProcessTrusted()` + `CGPreflightScreenCaptureAccess()`
on a 1 Hz timer (`PermissionsView.swift:9`). Cheap, but it runs whenever the tab
is *anywhere in the TabView*, not just when visible; a 2–3 s interval, or
restarting the timer `onAppear`/`onDisappear`, would be tidier.

---

## 3. Visual & layout

### V1 — The panel appears instantly, with no transition
**Conf: high · Eff: S**

`window.orderFrontRegardless()` and the panel is simply *there*. The native
switcher fades in over ~80 ms. A short opacity fade (and a 0.97→1.0 scale) would
make Zap feel materially more finished. The one catch is the layout-retry path
(`scheduleLayoutRetry`): the animation must start only once a real size is
committed, or it re-introduces the "small square" flash the retry exists to
prevent.

### V2 — The selected icon gets a highlight rect but no other emphasis
**Conf: medium** — a subtle scale (1.0 → 1.06) or a soft glow on the selection
would read faster at a glance, especially with `highlightOpacity` turned down.
Pairs with V1.

### V3 — Hidden and windowless apps look identical to active ones
**Conf: high · Eff: S** — see F1. Right now nothing in the row distinguishes an
app you've ⌘-H'd, an app with 12 windows, and an app with none. The native
switcher can't do this either; Zap easily could, and it's the sort of thing that
makes a replacement switcher obviously *better* rather than merely prettier.

### V4 — Window preview tiles letterbox awkwardly
**Conf: medium** — cells are a fixed 120×72 (`WindowGridMetrics`) and thumbnails
are `.fit`, so a portrait or ultrawide window sits in a big empty tile. Filling
the tile (`.fill` + clip) with the top-centre anchored would read better —
window previews are recognised by their top-left chrome, not their aspect ratio.

### V5 — No window title anywhere when the app row is focused
**Conf: high** — the header shows the *app* name; when the user arrows down into
a window, the header keeps showing the app name while the selection is a window.
Showing the focused window's title in the header (or the app name plus "· 3
windows") uses space that's already reserved.

### V6 — The panel's fixed two-thirds-up placement isn't configurable
**Conf: high · Eff: S** — `layout` hardcodes `visible.minY + visible.height *
2/3` (`OverlayWindowController.swift:556`). On a 27" display the panel sits
noticeably above centre. A three-way preference (centre / two-thirds / remember
where I dragged it) is cheap and the sort of thing people notice daily.

### V7 — Long app names truncate to the icon row's width
**Conf: medium** — `Text(...).frame(width: panelContentWidth)`
(`OverlayView.swift:21`) caps the name at the *icon row* width, which with 3–4
apps is narrow. "Microsoft Remote Desktop Connection Client" gets tail-truncated
where the panel could simply be a little wider for the name.

---

## 4. UX & interaction

### U1 — There is no in-switcher discoverability at all
**Conf: high** — Zap has an unusually rich key vocabulary: Tab / ⇧Tab / ` , ←→↑↓,
1-9, type-to-search, ⌫, Esc-Esc, hold-Q, hold-H, ⌘W, click, drag-and-drop onto
an icon. All of it is documented in the README and *nowhere in the app*. The
README even brags that "almost nobody knows the system switcher can do this" —
which is equally true of Zap's own features.

A hints footer toggled by `?` costs almost nothing: `?` is punctuation, so
`handleTypedCharacter` already ignores it, meaning the key is *free* — no
conflict with type-to-search whatsoever.

### U2 — First launch has no onboarding
**Conf: high** — the app installs a status item, maybe prompts for
Accessibility, and that's it. There's no "Zap is now handling ⌘-Tab, here's what
it can do" moment, and (per the README's own troubleshooting section) the
Accessibility grant is the single most common failure mode.

### U3 — The fallback mode can't be cancelled
**Conf: high** — carried from `awesome.md §2.1`. With Carbon ⌥-Tab there's no
key-up detection, so Esc never arrives and the auto-commit timer always fires.
At minimum the Settings caption should say so; better, the fallback could commit
on a second ⌥-Tab press to the current app.

### U4 — Secure Input silently disables the whole app
**Conf: high · Eff: S** — while any app has secure event input enabled (a focused
password field, some terminal emulators, 1Password's own fields), CGEventTaps
receive no key events and ⌘-Tab falls through to the *native* switcher with no
explanation. `IsSecureEventInputEnabled()` can detect this; surfacing it in the
Permissions tab (and dimming the menu-bar icon, as Pause already does) turns a
baffling intermittent failure into a legible one.

### U5 — Exclusions can only be set for *running* apps
**Conf: high** — `ExclusionsView.reload` lists running apps plus already-excluded
ones. You cannot pre-exclude an app that isn't running right now, which is
exactly when you'd want to (you're excluding it *because* you never use it). An
"Add App…" button with an `NSOpenPanel` scoped to `/Applications` closes this.

### U6 — No pinned / favourite apps
**Conf: medium** — MRU is the right default, but power users want two or three
anchors that are always at a known index so muscle memory ("⌘-Tab, 3") works.
This is the single most-requested feature in every third-party switcher.

### U7 — Nothing indicates *why* an app is missing from a scoped display
**Conf: medium** — per-display scoping silently drops apps. When the list is
scoped it would help to say so (a small badge on the panel: "this display only").
Right now a user who forgot the setting sees a mysteriously short switcher.

---

## 5. Missing features

### F1 — Hidden / window-count indication on icons
**Conf: high · Eff: S** — `NSRunningApplication.isHidden` is already consulted at
activation time (`SwitcherController.activate`). Carrying it into `AppInfo` and
rendering hidden apps at reduced opacity (with a small badge) is a handful of
lines and immediately makes ⌘-H legible. A window-count badge is the natural
companion, though it needs a cheap count source (the Quartz window list already
enumerated for scoping can provide it without extra AX calls).

### F2 — Configurable trigger hotkey
**Conf: high · Eff: M** — ⌘-Tab and ⌥-Tab are both hardwired. Needs a key-recorder
control; carried from `awesome.md §3.2`.

### F3 — Fuzzy / initials matching in type-to-search
**Conf: high · Eff: S** — `bestMatchIndex` handles prefix → word-prefix →
substring. It cannot match "vsc" → "Visual Studio Code" or "ppt" → "Microsoft
PowerPoint", which is precisely how people type when they're in a hurry. A
subsequence tier below substring (with the earliest/most-recent app winning
ties) is pure, cheap, and directly unit-testable in the existing
`TypeToSearchTests`.

### F4 — No app-switch history beyond MRU
**Conf: medium** — a "recently switched pairs" notion (Alt-Tab-style, but
per-project) is out of scope, but the switch counter already collected in
`Preferences` could power a "most-used apps" view in About.

### F5 — No localization
**Conf: high** — every string is a hardcoded English literal. SwiftUI's `Text`
takes `LocalizedStringKey` for free, so the app is *structurally* ready; there's
just no `.strings` catalog. Worth doing before this gets shared widely.

---

## 6. Accessibility

### A1 — Reduce Transparency and Reduce Motion are ignored
**Conf: high · Eff: S** — the panel is always an `NSVisualEffectView` blur, and
scroll/selection animations always run.
`NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency` and
`.accessibilityDisplayShouldReduceMotion` are one-line reads; honouring them is
the minimum bar for a system-level UI element that appears over everything.

### A2 — The overlay exposes no accessibility information
**Conf: medium** — icons are bare `Image`s with no labels. A borderless non-key
window is hard for VoiceOver to reach in the first place, so the practical value
is limited, but `accessibilityLabel(app.name)` costs nothing and makes the panel
legible to screen-recording/automation tools.

### A3 — No high-contrast consideration
**Conf: medium** — `labelColorHex` defaults to white on a 55%-opacity dark blur.
Over a bright wallpaper with low background opacity the app name can become
genuinely hard to read; there's no contrast floor and no
`accessibilityDisplayShouldIncreaseContrast` handling.

---

## 7. Code quality, architecture, tests

### C1 — `SwitcherController` is at 983 lines and doing five jobs
**Conf: high** — input routing, session state, type-to-search, quit/hide
lifecycle, window list, thumbnails, screen scoping. The pure bits have been
extracted well (that's why the tests are good), but the *stateful* session
machine — `isSessionActive`, `selectedIndex`, `typeBuffer`, `pendingShortcut`,
`quittingPIDs`, `windowSelectedIndex` — would benefit from being a `SwitcherSession`
value type with explicit transitions. That would also make B2/B8 testable rather
than reasoned-about.

### C2 — Test coverage stops exactly where the risk starts
**Conf: high** — 23 test files, all pure logic. Nothing covers session
lifecycle, commit/cancel, quit verification, or hover, because they're welded to
AppKit. Extracting the session machine (C1) is the unlock; a fake clock instead
of `Timer` would let the hold-vs-tap and quit-verification logic be tested
directly.

### C3 — Two `isRunningTests` implementations
**Conf: high · Eff: XS** — `AppDelegate.isRunningTests` and
`UpdateChecker.isRunningTests` are identical. One shared helper.

### C4 — Preferences is a 466-line god object with 30 `didSet` writers
**Conf: medium** — it works and it's readable, but every property repeats the
same `didSet { defaults.set(...) }` boilerplate. A small `@Stored` property
wrapper would remove ~120 lines and make it impossible to forget a key. Worth
doing only if it's touched again for another reason.

### C5 — Private SPI use is well-handled but undocumented in the README
**Conf: high** — `_AXUIElementGetWindow` and the four `CGS*`/SkyLight symbols are
both correctly treated as best-effort with `nil` fallbacks, and the trade-off is
explained in the source. It isn't mentioned in the README, where a user
evaluating a system-level tool would look for it. One sentence.

### C6 — `AppInfo.id` is `bundleID:pid` but MRU is keyed by bundle ID alone
**Conf: high** — deliberate and correct (documented in `ISSUES.md` High #6), but
the asymmetry deserves a note at the `MRUTracker` type level, since it's the
kind of thing a future change would "fix" by accident.

---

## 8. Novel, cool, delightful

Ordered by (my estimate of) charm-per-line-of-code.

### D1 — `?` for a key-hints footer ⭐
`?` is already ignored by type-to-search, so the key is free. A small footer
listing the live vocabulary — contextual, so it shows ⌘W only when a window is
focused — turns the app's best-kept secrets into discoverable ones. Cheap,
delightful, genuinely useful. (Implemented in this pass.)

### D2 — Number badges on hold ⭐
After the switcher has been up for ~600 ms without input, fade a tiny 1-9 badge
into each icon's corner. It teaches the number-jump shortcut passively, and it
looks like a heads-up display. Zero new key handling.

### D3 — Panel tint sampled from the selected app's icon
Pull the dominant colour from the highlighted icon and let the highlight (or a
subtle background wash) drift toward it as the selection moves. It makes the
panel feel *alive* and app-aware. Needs a cached per-bundle-ID colour so it
costs nothing on the hot path.

### D4 — Googly eyes decoration that track the highlight
From `awesome.md §4.4`, and still the best idea in that list: two xeyes in the
corner whose pupils follow the selected icon. The only decoration needing model
wiring, and the only one people would screenshot.

### D5 — "Surprise me" decoration
A meta-style that picks a random decoration each session. Zero drawing code.

### D6 — Boing-ball physics on idle
If the switcher stays open for several seconds with the Amiga decoration on, let
the ball actually *boing* — drop, bounce off the panel's bottom edge, rotate.
The raster machinery is already there; it needs a displaylink and a sine.

### D7 — A "zap" sound (off by default)
A 40 ms retro blip on commit. Ridiculous, opt-in, and exactly the sort of thing a
personal app is allowed to have.

### D8 — Switch-count milestones
The counter already exists in About. A one-off, tasteful notification at 1,000 /
10,000 / 100,000 switches ("You've zapped 10,000 times") is free delight from
data already on disk.

### D9 — Konami code
↑↑↓↓←→←→ then B, A while the switcher is open → the panel flips to the Amiga
theme with the boing ball for the rest of the session. All the input plumbing
already exists.

### D10 — Drag an icon out of the panel to pin it
If pinning (U6) happens, dragging an icon left/right to reorder — with the pinned
region visually separated — is the natural, discoverable interaction, and the
drop machinery is already wired for files.

---

## 9. What I'm implementing in this pass

High-confidence, self-contained, each on its own branch and PR:

| # | Entry | Branch |
|---|-------|--------|
| 1 | **B1** hover steals the selection | `claude/fix-hover-steals-selection` |
| 2 | **B2** stuck-session watchdog | `claude/fix-session-watchdog` |
| 3 | **B3** AX messaging timeout | `claude/fix-ax-messaging-timeout` |
| 4 | **B4** layout-aware Q/W/H | `claude/fix-layout-aware-action-keys` |
| 5 | **F1/V3** hidden-app indication | `claude/feat-hidden-app-indication` |
| 6 | **F3/B5** fuzzy search + no-match feedback | `claude/feat-smarter-type-to-search` |
| 7 | **D1/U1** `?` key-hints footer | `claude/feat-switcher-help-hints` |
| 8 | **A1** Reduce Transparency / Reduce Motion | `claude/feat-reduced-motion-transparency` |

Deliberately *not* attempted here: anything needing a live macOS session to
validate (V1 panel animation — the layout-retry interaction is too easy to get
wrong unseen), anything design-shaped (U6 pinning, F2 hotkey recorder), and the
architectural refactor (C1) which deserves its own focused pass with the session
machine extracted first.
