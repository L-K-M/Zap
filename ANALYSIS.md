# Zap — Analysis & Backlog

The living record of what's wrong, what's missing, and what would be fun — the
document future work starts from. Entries are removed as they ship.

**Provenance.** Consolidates the July 2026 review (`claude-review.md`), the
earlier `awesome.md` review (both merged here), and the October 2026 pass
(`mimo.md`, a local working file since discarded), and two November 2026
reviews. The second November review read every Swift file under `Zap/` (about
8,000 lines) end to end, plus the README, PLAN, ANALYSIS, CI workflows and the
test target. It rendered the overlay and the Appearance tab offscreen in a
scratch XCTest with real app icons, in every overlay state (default, search
badge, help footer, window list, preview grid, Amiga preset), which surfaced
B11, V8, V14 and V15 directly; `NSVisualEffectView` doesn't render offscreen,
so blur and vibrancy were judged from code. It also ran nine LongCat-2.5
reviewers (input layer, session state machine, data providers, performance,
overlay visuals, Settings, model/updates/security, product, tests/CI/docs),
each followed by an adversarial verifier: 129 raw findings, with every
important one spot-checked against the code. Its working notes (`tmp.md`,
never committed) are merged here.
`ISSUES.md` stays as the archived June 2026 review-and-resolution log.

**Scope.** Only unimplemented findings are listed. Entries fixed in merged PRs
(#16–#23 and earlier) are gone, as are entries with an open PR as of
2026-07→10: B6 (#53), B7+B9 (#58), B8 (#59), C3 (#60), C5 (#65), P2 (#64),
P4 (#57), P5 (#56), U4 (#55), and two small input nits (#61, #63). P1 is
*partially* addressed (#54 caches the scoped-display queries); what remains of
it is below. Work with an open PR from November 2026 is listed under
*Submitted in November 2026* instead of as a full entry.

**Verification.** The November 2026 reviews checked main at `5d1039d` on
macOS 27.0.1 and Xcode 27.2. The baseline suite passed 430–431 tests with one
skipped mirror-recovery case. Each finding below that depends on live behavior
lists what to reproduce or measure. The replacement hosted runner passed
its PR build on macOS 15 and Xcode 16.4.

**Labels** on entries from the second November review: *Verified* means
confirmed in code, an offscreen render, or a run; *Confirmed* means a verifier
confirmed it and a spot check agrees; *Plausible* means the mechanism is real
but the user-visible effect needs a live GUI session. *Idea* entries need a
design decision before code.

**Test seams worth knowing.** `EventTapKeyStateTests` (#99) drives the real tap
callback with synthesized `CGEvent`s through a fake `EventTapConnection`.
`SwitcherController(preferences:eventTap:isAccessibilityTrusted:)` (#98) lets a
test run the controller against a fake trusted tap. Several entries below are
testable with these once those PRs land.

---

## Start here

Shovel-ready picks, best value for effort first. Each links to its entry.

1. **B18 + B19** (S): two one-line input fixes, testable with #98's seams.
2. **B20 + B21** (S): number-jump fixes in `handleTypedCharacter`.
3. **B22** (S): hovering clears the search query.
4. **B25** (S): resolve the bundle URL before a file drop ends the session.
5. **B31 + B32** (S): display-scope persistence and MRU filtering.
6. **Bound AX window enumeration off the UI thread** (S–M): per-window AX
   timeout plus background enumeration.
7. **V11** (S): a top-lit panel edge; purely visual, very visible.
8. **A4** (S–M): VoiceOver announcements while cycling.
9. **F6** (S–M): ⌥ on release restores a minimized window, as the system does.
10. **P8** (M–L, the biggest win): move the event tap off the main thread.

Owner decision with the biggest payoff: **S2**, a stable signing identity so
updates keep the Accessibility grant. It needs a certificate created and
stored as a CI secret before any code changes.

---

## Submitted in November 2026

These changes have open PRs. Remove this tracking entry as each one ships.
Some came from parallel reviews and overlap; reconcile them when merging.

- Clarify that Option-Tab can be forced and also acts as automatic fallback.
  [PR #83](https://github.com/L-K-M/Zap/pull/83) (overlaps #92)
- Honor Reduce Motion for the search result badge.
  [PR #84](https://github.com/L-K-M/Zap/pull/84)
- Cancel obsolete thumbnail batches and share overlapping capture enumeration.
  [PR #85](https://github.com/L-K-M/Zap/pull/85)
- Add the opt-in Midnight preset.
  [PR #86](https://github.com/L-K-M/Zap/pull/86)
- Report theme file errors and save exports atomically.
  [PR #87](https://github.com/L-K-M/Zap/pull/87) (overlaps #97's import/export
  alerts)
- Move CI and release workflows off the retired macOS 14 runner.
  [PR #88](https://github.com/L-K-M/Zap/pull/88). Until it lands, every
  `Build & Test` job, `main` included, is rejected (since about 2026-11-17)
  with "The configuration 'macos-14-arm64-us-default' is not supported". The
  fix is a supported `runs-on` image plus a `setup-xcode` pin to an Xcode that
  image ships.
- Keep shortcut help readable with a short icon row.
  [PR #89](https://github.com/L-K-M/Zap/pull/89)
- Keep the sample symbols in Appearance legible across system appearances.
  [PR #90](https://github.com/L-K-M/Zap/pull/90)
- B11 + V8 + C8: give minimized windows a real glyph (`macwindow.badge.minus`
  doesn't exist, so rows drew no icon and misaligned), leading-align the
  preview grid's last row so it matches row-major arrow navigation, and add a
  test that every literal SF Symbol name in the app resolves.
  [PR #91](https://github.com/L-K-M/Zap/pull/91)
- B12 + B13: label the trigger toggle "Use ⌥-Tab instead of ⌘-Tab" (it forces
  ⌥-Tab; it is not a fallback), and drop the stale "relaunch after granting
  Accessibility" advice from Permissions and the README.
  [PR #92](https://github.com/L-K-M/Zap/pull/92) (overlaps #83)
- U12: tell identical displays apart in the Displays pickers by position
  (left/right, top/bottom) or number.
  [PR #93](https://github.com/L-K-M/Zap/pull/93)
- V7: capture window previews at the display's backing scale; they were
  upscaled about 1.5× on Retina.
  [PR #94](https://github.com/L-K-M/Zap/pull/94)
- U10: opening Zap again (Spotlight, Finder) shows Settings.
  [PR #95](https://github.com/L-K-M/Zap/pull/95)
- U9: the status menu and tooltip say when ⌘-Tab isn't intercepted, with an
  "Open Accessibility Settings…" item; the status button gets a VoiceOver
  label. [PR #96](https://github.com/L-K-M/Zap/pull/96)
- B14 + B15: Appearance "Reset to defaults…" asks first and also resets icon
  bleed, trim and shadow; theme import and export failures show an alert.
  [PR #97](https://github.com/L-K-M/Zap/pull/97) (overlaps #87)
- B34: toggling "Use ⌥-Tab instead of ⌘-Tab" applied the old value, because
  the `$useAlternateHotkey` sink re-read the preference during `willSet`;
  turning it on never released ⌘-Tab until relaunch.
  [PR #98](https://github.com/L-K-M/Zap/pull/98)
- B16 + B17: a lost key-up no longer leaves a stale record that swallows the
  next release of that key in any app, and a tap-disabled notification no
  longer re-enables a tap that Pause turned off.
  [PR #99](https://github.com/L-K-M/Zap/pull/99)
- P10 (first half): give the three always-on 2 s polls a 0.5 s tolerance so
  macOS can coalesce them. The second half is under P7.
  [PR #100](https://github.com/L-K-M/Zap/pull/100)
- U11: ↓ opens the window list immediately instead of waiting out the dwell,
  and Esc steps back (query, then window focus, then the session).
  [PR #101](https://github.com/L-K-M/Zap/pull/101)
- P11: recycle the 30-minute-old overlay window after `hide()` instead of on
  the next ⌘-Tab; the old window is now closed, not just hidden.
  [PR #102](https://github.com/L-K-M/Zap/pull/102)

## Important

### P1 — The keystroke path still snapshots every running application

`beginSession` asks `AppListProvider.currentApps` to snapshot each running
app, resolve icons, apply scope/exclusions, and MRU-sort synchronously. Scoped
window-server queries are already cached. Measure app-list and session-open
latency at 5 and 40 apps, with cold and warm icons and with scoping. The show
delay does not defer these operations. A system-icon probe with five apps
measured 18.82 ms on first use, then 0.054 ms median and 0.062 ms p95 across
60 warm calls. Measure a crowded row and Pict resolution before changing
snapshot caching.

First move scope and exclusion filtering ahead of icon substitution. If the
snapshot remains significant, maintain membership and stable metadata on
workspace changes, with an initial synchronous seed and an invalidation path.
Evaluate MRU and hidden state at session start. Test launch, quit, hide, display
scoping, wrapper bundles, and rapid back-and-forth switching.

P8 is the root cause that makes this matter: even a fast snapshot runs on the
main thread that every keystroke on the Mac waits for.

### P8 — Every keystroke on the Mac waits on Zap's main thread

performance — important · Verified (architecture)

`SystemEventTapConnection` adds the tap's source to `CFRunLoopGetMain()`
(line 21), and the tap is an active filter (`.defaultTap`). WindowServer holds
each keyboard event in every app until Zap's callback returns, and that
callback can't run while the main thread is busy. Whatever occupies the main
thread therefore delays typing system-wide: SwiftUI layout of the panel
(`layoutSubtreeIfNeeded` + `fittingSize` on every show and resize), the
synchronous dwell-time AX enumeration (next entry), a modal update alert
(B10), the Settings window and its live preview. Stalls of about a second get
the tap disabled, which is the failure mode the stranded-session watchdog and
`docs/hotkey-diagnostics.md` exist for. It is the root cause behind P1, B10,
B16 and B17.

Fix: give the tap its own thread and `CFRunLoop` (QoS `.userInteractive`). Keep
the consume/pass decision on that thread with a tiny lock-protected state
(session active, held shortcut key codes, intended-enabled); the tap thread
sets "session active" itself on ⌘-Tab, so keys typed before the main thread
catches up are still consumed. Dispatch every action (cycle, commit, type, …)
to main asynchronously, and let main clear "session active" when a session
ends or turns out empty. Effort M–L. Verify fast ⌘-Tab bursts, Secure Input,
tap timeouts and pause/resume live.

### Bound AX window enumeration off the UI thread

`SwitcherController.revealWindows` synchronously invokes
`WindowEnumerator.windows`, which does 5–6 AX round trips per window (role,
subrole, `_AXUIElementGetWindow`, title, minimized, plus chrome probes for
Finder). A standalone probe measured 3.46 ms for a four-window app and
255.92 ms for an isolated suspended process (1.87 ms when responsive). The
configured 0.25 s messaging timeout applies per AX call, but it is set only on
the application element; window elements copied out of it very likely keep
the system default timeout (seconds), so an app that answers `AXWindows` and
then stalls can freeze the panel and, through P8, all typing.

Move read-only enumeration to a bounded background worker (AX is usable
off-main) and set the timeout on each window element too. Check cancellation
between AX calls and apply results on the main thread only for the current
session and selected process: capture the pid and a generation counter before
enumerating and compare both on return (`windowsGeneration` already guards
thumbnails this way; the reveal itself has no such check today). Keep raise
and close on their current path. Verify Tab, Escape, and Command release
during a slow dwell, and confirm no stale list appears after changing
selection or starting a new session. Effort S–M.

### Verify window closure before dropping the row

`WindowEnumerator.close` reports whether AX accepted a button press.
`SwitcherController.closeFocusedWindow` immediately removes that row. A
document with unsaved changes shows a save sheet and stays open, but vanishes
from the list. Reproduce with a disposable unsaved document that prompts to
save, then cancel the prompt. If the row disappears while the window stays
open, mark the close pending until the AX window is gone (re-enumerate after a
short delay, or watch `kAXUIElementDestroyedNotification`). Allow navigation
while pending and prevent key repeat from pressing that same close button
again.

### S2 — Updates silently cost the Accessibility grant; sign with a stable identity

distribution — important · Idea (needs the owner's certificate) · high value

Releases are ad-hoc signed, so each build has a new code-directory hash and
TCC treats the update as a new app: after updating, Zap quietly falls back to
⌥-Tab (U9's menu warning, #96, at least makes that visible). A self-signed
code-signing certificate kept as a CI secret (no Apple Developer account
needed) gives a stable designated requirement, so grants survive updates. Add
`--options runtime` while at it: `ENABLE_HARDENED_RUNTIME=YES` is set, but the
shipped app isn't hardened-runtime signed.

Until then, detect "trusted on the previous version, untrusted now" (persist
the last trusted version) and show a one-time explainer with "Open
Accessibility Settings" and how to remove the stale entry.

## Nice-to-have

### B10 — An update alert can appear on top of a live switch session

bugs — nice-to-have

`UpdateChecker.performCheck` can present a modal alert after a background
check while a switch is active. The tap runs in common modes, so a modal alert
can also see new switch attempts. Inject an update result during a switch to
reproduce. Defer the alert until commit or cancel and suspend interception
while the alert owns input. Verify the original switch completes and the
alert appears only once. With P8, the modal run loop is also what the tap
callback waits behind.

### Real-window thresholds disagree inside one feature area

bugs — nice-to-have

`WindowEnumerator.isDocumentSized` counts windows ≥120×120 while
`ScreenWindowScoper.minWindowSide` is 80: a 100×100 window counts toward
display scoping but is dropped from the off-Space window list.

Suggested fix: one shared constant, with a comment on why it has its value.

### B18 — "?" doesn't resolve an armed ⌘Q/⌘H hold

bugs — nice-to-have · Confirmed

Every other key mid-session resolves a pending Q/H press as a tap
(`cancelPendingShortcut()` in typing, Backspace, arrows, Esc). `toggleHelp()`
in `SwitcherController` does not, so "q" then "?" within the hold window,
with Q still down, lets the hold timer fire and quit or hide the highlighted
app. Fix: call `cancelPendingShortcut()` first in `toggleHelp()`. Test with
#98's controller seam: arm a hold, toggle help, spin past
`shortcutHoldDelay`, assert nothing quit.

### B19 — Switching the trigger mid-session strands the session

bugs — nice-to-have · Confirmed

`applyInputMode()` tears down the tap without ending a live session. If it
runs during an event-tap session, `usesEventTap` becomes false, so the
stranded-session watchdog (which requires `usesEventTap`) never fires. The
tap is gone, so keys reach the front app again, but the panel stays up with
nothing to commit or cancel it until the next ⌥-Tab cycle or its auto-commit.
`refreshInputModeIfNeeded` already calls `cancel()` first; `applyInputMode`
itself should, when a session is active.

### B20 — Number jump vs. pending-quit apps

bugs — nice-to-have · Confirmed

`handleTypedCharacter` computes `numberJumpIndex` over all names, quitting
apps included. A digit naming a dimmed app calls `pick()`, which silently
refuses, and the digit is lost (not added to the query either). A quitting app
whose name starts with that digit also suppresses the jump for everyone. Fix:
compute both over selectable apps and fall through to search on a refused
jump.

### B21 — ⇧ + digit triggers jump-and-commit

bugs — nice-to-have · Confirmed

`EventTapMonitor.typedCharacter(for:)` clears every modifier, so ⇧1 (`!` on
US layouts) reads as `1` and commits a switch to the first app. Read digits
with Shift honoured and skip the jump when the shifted character isn't a
digit. Testable with `EventTapKeyStateTests`' synthesized events (#99).

### B22 — Hovering after typing leaves a stale query badge

bugs — nice-to-have · Verified

`hoverApp` moves the selection but leaves `typeBuffer` and the badge, so the
badge says "saf" while the highlight sits on Mail. Clear the query (and any
armed hold) when hover takes over.

### B23 — Clearing the query keeps the highlight on the last match

bugs — nice-to-have · Idea

Type "saf", press Esc (or Backspace to empty): the badge disappears but the
highlight stays on Safari, so releasing ⌘ switches there. Spotlight behaves the
same way, so this is a judgement call. Restoring the pre-query selection is
probably what people expect.

### B25 — A file drop dismisses the switcher even when it can't open

bugs — nice-to-have · Confirmed

`openFiles` calls `endSession()` before resolving the app's bundle URL. If the
app has just quit, the panel vanishes and nothing opens. Resolve first, then
end the session.

### B26 — Refused-quit verification throws away a hand scroll

bugs — nice-to-have · Confirmed

`verifyQuit` → `overlay.setQuitting` → `scrollToCenter` re-centres the row even
though the selection didn't change. Skip the scroll when the index is
unchanged.

### B27 — Stranded-session recovery can yank focus after the user moved on

bugs — nice-to-have · Confirmed

The watchdog commits about 0.8 s after a missed ⌘ key-up. If the user has
meanwhile clicked into another app, `commit()` activates the old selection over
it. Cancel instead of committing when the frontmost app changed since the
session began.

### B28 — Fallback auto-commit can beat the show delay

bugs — nice-to-have · Confirmed

In ⌥-Tab mode the auto-commit fires after 0.8 s regardless of `showDelayMs`
(the slider stops at 250 ms, but a stored value is accepted up to 1000 ms;
themes don't carry the delay). Above 800 ms
the user gets a switch with no switcher ever shown. Use
`max(0.8, showDelay + 0.3)`.

### B29 — Late thumbnail captures repopulate a cleared cache

bugs — nice-to-have · Confirmed

Turning previews off calls `thumbnails.clear()`, but in-flight captures insert
afterwards (`WindowThumbnailProvider.thumbnail(for:)` has no epoch). Add an
epoch bumped by `clear()`. Check against #85, which reworks thumbnail batches.

### B30 — Off-Space full-screen windows never get previews on macOS 14+

bugs — nice-to-have · Confirmed

`captureModern` looks windows up in
`SCShareableContent(onScreenWindowsOnly: true)`, which excludes exactly the
off-Space windows `includeFullScreenWindows` adds. Fall back to the legacy
capture when the window isn't in the content (it may still fail; it is
best-effort either way), or drop the promise in the comment.

### B31 — Per-display scope settings are fragile

bugs — nice-to-have · Confirmed

- `ScreenIdentity.persistentID` falls back to a session-scoped `display-<id>`
  and persists scope modes under it; after a reboot the setting points at
  nothing, or at a different display. Return nil instead and don't offer
  scoping for that display.
- `Preferences.init` casts the stored per-display dictionary to
  `[String: String]`; one wrong-typed value discards every display's mode.
  Load `[String: Any]` and drop only the bad entry.

### B32 — MRU order records activations that can never be shown

bugs — nice-to-have · Confirmed

The activation observer in `AppListProvider` records excluded apps and
accessory agents too, and `MRUTracker.order` is never pruned, so they push
real apps out of the 50-entry persisted prefix. Filter to `.regular`,
non-excluded apps.

### B33 — Updater edge cases

bugs — nice-to-have · Confirmed

- `SemanticVersion` compares pre-release identifiers lexically: `beta.10` <
  `beta.2`. Only matters if prereleases are ever enabled.
- A tag that fails to parse is reported as "You're up to date" and still
  stamps `lastCheckDate`, skipping the next 24 h of background checks.
- `preferredAsset` falls back to any asset (a checksum file, notes), which
  would be "downloaded as the update". Restrict to dmg/zip.
- `checkNow()` guards only `isChecking`. The Settings button is disabled while
  checking or downloading, but the status-menu "Check for Updates…" item
  silently no-ops during a check and starts another check during a download.

### P3 — The whole overlay body re-evaluates on every model change

performance — nice-to-have

`AGENTS.md` states the invariant — "only move the selection highlight on Tab,
do not rebuild the whole view" — but `selectedIndex` is `@Published` on the
same object as everything else, so `OverlayView.body` re-runs entirely per Tab
press, re-creating each icon's `dropDestination`, `onTapGesture`, `onHover`,
the gradient `GeometryReader` and the CRT canvas. SwiftUI absorbs it at ~10
icons; at 40 with large icons it's measurable. The same happens for each
window thumbnail that arrives (`windowThumbnails` is `@Published`), and
`show()`/`hide()` publish 9–10 properties in a row.

Suggested fix: `Equatable` leaf views for icon cells (taking
`isSelected: Bool`) and thumbnails, so unchanged cells skip re-evaluation.
Measure with a body-evaluation counter first.

### P7 — Poll permission status only while the pane is visible

performance — nice-to-have

`PermissionsView` queries Accessibility, Screen Recording, and Secure Input
every second. The current AppKit tab host mounts panes lazily. The second
November review read the 1 Hz Combine timer as running whenever its pane has
been loaded, visible or not; confirm with a trace whether the subscription
stops when a mounted pane is hidden or Settings is closed. If it continues,
start and stop it with pane visibility and refresh immediately on return from
System Settings.

Second half of P10 (the first half, timer tolerance, is #100): the input-health
tick, the tap diagnostics tick and the Secure Input tick each still run every
2 s. Each health tick issues `CGGetEventTapList` twice plus
`AXIsProcessTrusted()`, and the input-mode refresh repeats the same queries.
Fold them into one tick that shares one
`registeredEvents` snapshot.

### P12 — Commit does avoidable work before the switch

performance — nice-to-have · Confirmed

`commit()` calls `preferences.recordSwitch()` before `endSession()`: three
`UserDefaults` writes plus two `@Published` changes on the object the overlay
observes, so the whole panel (and any open Settings pane) re-renders at the
exact moment the target app is being activated, inside the tap callback. Move
the counters to a small `SwitchStats` object (only About observes it) and
record after `endSession()` on the next run-loop turn.

### P14 — Collapsing the window list on Tab costs a full relayout

performance — nice-to-have · Confirmed

With a list showing, the first Tab runs `clearWindows` → `layout(keepTop:)`
(`layoutSubtreeIfNeeded`, `fittingSize`, `setFrame`, mirror sync)
synchronously in the tap callback. Defer the collapse to the next run-loop
turn, or keep the list until the new dwell fires.

### P15 — Smaller hot-path costs

performance — nice-to-have · Confirmed

- Every Tab key-down system-wide (no ⌘ needed) formats a string and enqueues an
  `os_log` at `.notice` (persisted) for diagnostics. Keep the counters, drop
  the per-press line or gate it behind a launch argument.
- Every swallowed key-down mid-session reads the Unicode string twice (once for
  "?", once plain).
- Type-to-search rebuilds and re-lowercases `apps.map(\.name)` per keystroke.
- `scheduleVisibilityCheck` runs `CGWindowListCopyWindowInfo` on main 0.2 s
  after every reveal, once per mirrored window.
- With `includeFullScreenWindows`, each reveal copies the whole system window
  list again even though scoping just did; share a short-TTL snapshot.
- `warmIconCache` enumerates on main at launch and warms agents (filter to
  `.regular`); its comment says "off the main thread".

### V1 — The panel appears instantly, with no transition

visual and layout — nice-to-have

`orderFrontRegardless()` and it is simply there; the native switcher fades in
over ~80 ms. A short opacity fade (plus a 0.97→1.0 scale) would make Zap feel
materially more finished. The animation must start only once
`layout(keepTop:)` has committed a real size, or it re-introduces the
small-square flash the retry path prevents. Wants a live session to tune.

### V2 — The selected icon gets a highlight rect and nothing else

visual and layout — nice-to-have

Try a crisp selection outline with Increase Contrast or when the theme uses
a faint highlight. A subtle scale (1.0 → 1.06) or soft glow is another visual
option. Test over bright and dark backdrops at low highlight opacity. Keep
the outline visible under Reduce Motion and suppress animated scale there.

Motion makes it read as premium too: one highlight view that slides between
cells with a short spring (`matchedGeometryEffect` or an offset keyed by
index) makes fast ⌘-Tab bursts legible. Keep it a single view so P3 stays
cheap, and respect Reduce Motion. See also *Selection echo*.

### V3 — Window preview tiles letterbox awkwardly

visual and layout — nice-to-have

Cells are a fixed 120×72 and thumbnails are `.fit`, so a portrait or
ultrawide window sits in a mostly-empty tile. Filling the tile (`.fill` +
clip, top-anchored) would read better: window previews are recognised by
their top-left chrome, not their aspect ratio.

### V4 — Show the focused window title in the header

Window tiles and list rows show truncated titles. The header continues to show
the app name even while a window is highlighted. Show the focused title in
the existing header and expose the full title and minimized state through
accessibility. Verify long and identical titles, an empty title, and return to
the app row without resizing the panel.

### V5 — Where the panel appears isn't configurable

visual and layout — nice-to-have

Vertically, `layout` hardcodes `visible.minY + visible.height * 2/3`. On a 27"
display that's noticeably above centre. A three-way preference (centre /
two-thirds / remember where I dragged it) is cheap and noticed daily.

Which display: the panel follows the pointer (`targetScreen`). Offer "display
with the focused window" and "main display" too; laptop-plus-monitor users
usually want it where they are working.

### V6 — Long app names truncate to the icon row's width

visual and layout — nice-to-have

The name is framed at `panelContentWidth`, which with 3–4 apps is narrow, so
long names tail-truncate where the panel could simply be a little wider for
the label.

### V9 — The default look ignores the system's appearance and accent colour

visual and layout — Idea · Confirmed

The panel is always dark, with a flat, saturated `#0A84FF` highlight at 85%.
Edge, badge ring, thumbnail outline and capsule fill are hard-coded white or
black in `OverlayView`, so light themes lose their edges. The native switcher
follows Light/Dark and uses a neutral highlight. A "System" theme as the
default (material by appearance, highlight from `controlAccentColor` at lower
opacity or neutral white, `labelColor` text), plus a luminance-aware chrome
colour for custom themes, would make Zap feel native. Changes the default
look, so it's the owner's call. Pairs with A3 and V10.

### V10 — Liquid Glass on macOS 26+

visual and layout — Idea

On Tahoe, SwiftUI's `glassEffect(_:in:)` gives the panel the system's own
glass, matching the native switcher. Keep the `.hudWindow` blur as the
fallback, and guard with `#available` plus `#if compiler(>=6.2)` so CI's
Xcode 16 toolchain (16.2 today, 16.4 with #88) keeps building. Needs a live look; pairs with V9.

### V11 — The panel edge is one flat 8% hairline

visual and layout — nice-to-have · Confirmed

The panel stroke in `OverlayView` is a single white 8% line. Native panels
catch light at the top and have a dark outer line. A top-lit gradient stroke
(white ~0.22 → 0.04) inside, plus a 0.5 pt outer black ~0.2, survives both
bright and dark wallpapers. Cheap, purely visual.

### V12 — The window shadow is never invalidated after the panel resizes

visual and layout — nice-to-have · Plausible

`window.hasShadow = true` and the panel's size changes constantly (window
list, badge, help footer), but nothing calls `invalidateShadow()`. For a
non-opaque borderless window AppKit derives the shadow from the content's
alpha and can keep a stale silhouette after the content changes. Look at it
live, grow and shrink the list, and add the call to `forceDisplay()` if it
lags.

### V14 — The Amiga ball hides the last icon

visual and layout — nice-to-have · Verified (render)

At the preset's size the boing ball is about 1.2× the header height and sits
under the last one or two icons. A glassy macOS 26 icon over a high-contrast
checkerboard is hard to read. Shrink the default, keep the ball inside the
corner above the row, or soften the decoration under icon cells.

### V15 — The Appearance preview misrepresents the panel

visual and layout — nice-to-have · Verified (render)

- `AppearanceView.preview` applies `.scaleEffect(0.7)` to a panel with
  `.fixedSize(vertical: true)` inside a 150 pt frame. At icon 128 and padding
  60 the drawn panel is about 206 pt tall: clipped at the top and spilling over
  the divider and form below.
- The stand-in icons are SF Symbols (`hammer.fill`, `app.fill`,
  `square.fill`), rendered as a blue hammer and two flat grey blobs, so the
  preview doesn't look like a switcher.
- `VisualEffectBlur` blends `.behindWindow`, so inside Settings the preview
  shows the desktop behind the Settings window.
- The preview builds a fresh `OverlayModel` in a computed property on every
  body evaluation (formerly P6), so it can hold no state and re-allocates per
  slider tick; the width cap and scrolling are never shown.

Fix: scale-to-fit inside a clipped frame, use the icons of the user's top MRU
apps (symbols as fallback), blend `.withinWindow` in the preview, hold the
model in `@StateObject`, and give it a realistic `maxContentWidth`. Check
against #90, which touches the sample symbols.

### V16 — Smaller visual nits

visual and layout — nice-to-have · Confirmed

- The grid titles are 11 pt, the list titles 13 pt; the same list changes type
  size when previews toggle.
- Fractional cell widths (icon × (1 + 2·bleed)) put the panel edge and the 1 pt
  border on half-pixels; snap the committed frame to the backing scale.
- Turning off "Show app name" shrinks the boing ball about 18% and shifts the
  gradient, because both derive from the name-inclusive header height.
- The Settings window's minimum width comes from the tab row (around 650 pt
  with seven tabs), not the content (520 pt), so forms stretch wide.
- Permissions and About don't use the grouped `Form` style of the other panes.

### U2 — First launch has no shortcut practice

`AppDelegate` creates the menu bar item and may prompt for Accessibility.
The overlay's `?` footer covers in-session help. Start with an optional
Settings practice card for one forward and one reverse switch. Offer a
permission action when needed and explain the actual alternate trigger mode.
Verify a fresh install and the denied-permission path.

### U3 — The fallback mode can't be cancelled, or do much at all

usability — nice-to-have

With the Carbon ⌥-Tab hotkey there is no key-up detection, so Esc never
arrives and the 0.8 s auto-commit timer always fires. More broadly, no keys are
monitored in fallback mode: type-to-search, 1–9, hold-⌘Q/H, arrows, Esc and
"?" are all dead, and whatever the user types goes to the app they're leaving.
That is inherent without Accessibility. At minimum say so in the Settings
caption, the Permissions tab and the README; let a second ⌥-Tab onto the
current app act as a cancel; and consider making the panel key for fallback
sessions (Zap activates; it can then read keys locally) as an opt-in.

### U5 — Exclude an installed app that is not running

`ExclusionsView` lists running apps and existing exclusions. Add an “Add
App…” picker starting at Applications, validate the selected bundle ID, write
through the existing exclusion store, and show the offline row immediately.
Test a duplicate selection, an invalid bundle, and re-enabling an exclusion.

### U6 — No pinned / favourite apps

usability — nice-to-have

MRU is the right default, but two or three anchors at fixed indices make
muscle memory ("⌘-Tab, 3") work. The most-requested feature in every
third-party switcher. Design decision first, code second.

### U7 — Nothing indicates why an app is missing from a scoped display

usability — nice-to-have

Per-display scoping can show a surprisingly short list. Show a compact
“This display only” marker when the scope actually filters the row. Verify
the excluded-app override, hot-plug, differences by pointer display, and
mirroring.

### U8 — Session app list is a snapshot

usability — nice-to-have

Apps launched or quit outside Zap's own ⌘Q path aren't reflected until the
next session. A deliberate trade-off for a stable hot path; commit safely
no-ops on a vanished app. Listed so it isn't rediscovered as a bug.

### U14 — Small Settings and menu papercuts

usability — nice-to-have · Confirmed

- The Exclusions and Icons lists only refresh on appear or Refresh; observe
  launch and quit notifications (debounced).
- The Displays caption is about 90 words; use one line plus a "Learn more"
  popover.
- Slider ranges are narrower than the stored clamps. Icon size is 48–128 on
  the slider but 24–256 in `Preferences` and `AppearancePreset`, so an
  imported theme can pin the slider at its end and the next drag silently
  changes the value. The show delay is 0–250 on the slider but 0–1000 when
  loaded from defaults. Align them.
- Exclusions and General have no reset.
- The README promises 1–9 always jump; the code (correctly) lets
  digit-prefixed names like "1Password" win.
- The status menu has no About item, and the About pane has no links (GitHub,
  licence, release notes).
- The `?` hints keep offering "pause for windows" (with #101, "↓ or pause for
  windows") after the dwell has looked and found fewer than two windows, and
  show "esc cancel" while Esc would first clear a search query.
  `OverlayView.helpHints` needs "a list can still appear" and "query active"
  inputs from the controller.

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
no `.strings` catalog. Worth doing before this is shared widely. Strings built
by interpolation (for example the display-position suffixes from #93) need
`String(localized:)`.

### F6 — ⌥ on release restores a minimized window

missing features — nice-to-have · Verified (absent)

In the system switcher, holding ⌥ when releasing ⌘ restores the app's
minimized window. Zap's `flagsChanged` commit already sees the flags: pass
`.maskAlternate` through `onCommit`, then commit via
`NSWorkspace.openApplication(at:configuration:)` (LaunchServices sends the
reopen event, so the app un-minimizes or opens a window exactly like a Dock
click), or un-minimize via AX. Edge case: two instances sharing one bundle URL.

### F7 — Type-to-search across window titles

missing features — Idea

When a window list is showing, typing could filter or jump the windows by
title ("inbox" → Mail's Inbox window). An all-windows mode (every window of
every app as tiles) is the larger version of the same idea.

### F8 — Launch apps that aren't running

missing features — Idea

When a query matches no running app, offer the best installed match as a
ghost tile ("Open Xcode"); releasing ⌘ launches it. Index `/Applications` via
`NSMetadataQuery` off the hot path. Turns the switcher into a launcher for
free.

### F9 — Recently quit apps as ghost tiles

missing features — Idea

Keep the last two or three quit apps (from `didTerminateApplication`) as
dimmed tiles at the end of the row; choosing one relaunches it. "Oops, I just
quit that" in one keystroke.

### F10 — Dock badges and audio indicators on icons

missing features — Idea

Show the Dock's badge counts (Mail unread, Messages) by reading the Dock's
`AXStatusLabel`, and a small speaker on apps currently playing sound
(CoreAudio process objects, macOS 14.4+). Both answer "where was that coming
from?" at a glance.

### F11 — More switcher modes and controls

missing features — Idea

- A visual ⌘-\` window switcher for the front app, reusing the grid.
- "Sticky" mode: double-tap ⌘-Tab to keep the panel open after ⌘ is released,
  for mouse picking.
- Per-app hotkeys (⌥⌘1 → Mail).
- ⌥⌘H hide others, ⌥⌘W close all from inside the switcher.
- A `zap://` URL scheme or App Intents for Shortcuts.

### F13 — Menu bar conveniences

missing features — nice-to-have

Timed pause ("Pause for 15 minutes / 1 hour / until tomorrow"), an option to
hide the menu-bar icon (safe once reopening Zap shows Settings, #95), and a
"Recent apps" submenu.

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

### A4 — VoiceOver hears nothing while you cycle

accessibility — nice-to-have · Verified

The overlay is never key, so trait changes aren't announced. Post an
`NSAccessibility` announcement ("Safari, 2 of 7", "hidden") on selection
changes while VoiceOver is running (`NSWorkspace.shared.isVoiceOverEnabled`).
Also: icon cells carry `.isButton` but expose no action, window rows don't
expose their selected state, and the Icons row menu button has no label.

### S1 — Update downloads are unverified

security — nice-to-have · Confirmed

`UpdateDownloader` saves whatever the release asset URL serves: no checksum or
signature check, the file gets no quarantine attribute (Zap doesn't set
`LSFileQuarantineEnabled`), and `asset.name` becomes the filename unsanitised
(GitHub strips `/`, but nothing here relies on that). Exposure is low (TLS to
GitHub, owner's repo), but a tampered asset would skip Gatekeeper's
first-launch check entirely. Sanitise the name (last path component, no
leading dot), publish SHA-256 sums in the release body and verify them, and
decide deliberately about quarantine.

### S3 — Build hygiene

security — nice-to-have · Confirmed

- `release.yml` publishes from a tag without running the tests.
- PictKit tracks `branch: main`; pin a tag or revision range.
- `scripts/*.sh` exec tools resolved from `PATH`.

### C1 — Extract the switcher session transitions

code quality — nice-to-have

Input routing, session state, type-to-search, quit/hide lifecycle, window
list, thumbnails, screen scoping. The pure bits are extracted well (which is
why the tests are good), but the *stateful* session machine — `isSessionActive`,
`selectedIndex`, `typeBuffer`, `pendingShortcut`, `quittingPIDs`,
`windowSelectedIndex` — wants to be a `SwitcherSession` value type with
explicit transitions. That's also the unlock for C2.

### C2 — Test coverage stops exactly where the risk starts

code quality — nice-to-have

The suite covers individual input rules and some AppKit presentation paths.
There is still no end-to-end test for session lifecycle, commit/cancel, quit
verification, hold-vs-tap, or dwell sequencing. Extract the session
transitions (C1) and test them with a fake clock; #98's controller seam is a
start. Specific gaps carried forward: reverse-cycling, commit/cancel,
launch-at-login (needs an injectable `SMAppService` seam), the fallback-hotkey
preference path (#98 adds a first test for the toggle), the timer/callback
wiring behind the stranded-session rule (the rule is tested; the path is
not), the UpdateChecker throttle, skip and error paths, and the MRU observer.
Also:

- `PreferencesTests` builds dates with `Calendar.current` and fails on
  non-Gregorian device calendars; use the Gregorian calendar the
  implementation uses.
- `testHelpKeyIsNotASearchCharacter` asserts a standard-library fact.
- macOS 13, the deployment target, is never exercised in CI.

### C4 — `Preferences` is a 500-line object with ~30 hand-written `didSet` writers

code quality — nice-to-have

It works and reads fine, but a small `@Stored` property wrapper would remove
~120 lines and make it impossible to forget a key. Worth doing only when it's
being touched anyway. Watch the Combine trap B34 hit: `@Published` emits from
`willSet`, so a sink must use the emitted value or hop with
`.receive(on: RunLoop.main)` before reading the property back.

### C7 — Unit tests host the real app binary

code quality — nice-to-have

The `isRunningTests` guard (now one definition, PR #60) keeps global hooks
from being installed; a separate pure-logic test bundle would remove the need
for the guard entirely.

### C9 — Swift 6 readiness

code quality — nice-to-have · Confirmed

`Task { [weak self] … await self?.applyWindowThumbnail }` sends a non-Sendable
controller across actors, and `ActivationHandoff` / `WindowEnumerator` keep
static mutable state. Mark the controllers `@MainActor` before attempting the
Swift 6 language mode (the project is on Swift 5 mode today, so nothing is
broken yet).

### C11 — Dead code and duplication

code quality — nice-to-have · Confirmed

`acknowledgedSearchProviders` is a persisted preference nothing reads any more
(icon search moved to Pict). Clamp, colour and angle validation is duplicated
between `Preferences` and `AppearancePreset`. `MainMenu` comments still mention
`SVGRasterizer` and the icon-search sheet. `SwitcherInputMode.isEventTap` has
no callers at all. The `character == nil` branch in Q/H routing is
unreachable.

### C12 — Presets don't carry the icon-artwork settings

code quality — nice-to-have · Confirmed

Bleed, trim and shadow aren't in `AppearancePreset`, so a shared theme doesn't
reproduce its look. Add them as optional fields so old files still decode;
today one missing or wrong-typed field rejects the whole file.

### C13 — Docs drift

code quality — nice-to-have · Confirmed

PLAN.md's Settings and menu lists, structure and milestones predate the Pict
split. SHARED-ICONS.md's status section contradicts the shipped integration.
`WindowNavDirection`'s doc says ←/→ are no-ops in the list (they move the app
selection).

## Delight backlog

Ordered roughly by charm-per-line-of-code. D1 (the `?` hints footer) shipped
in PR #22.

### Hold-to-act progress

`SwitcherController.handleShortcutKey` tentatively types Q or H, then rolls
that back on a hold. Show a small progress ring on the original action target
and a static label under Reduce Motion. Verify tap-to-search, early release,
Tab, pointer movement, and a disappearing target.

### Preset browsing (D11 — theme gallery)

`AppearanceView` applies a built-in theme immediately from a menu. Prototype
a keyboard-accessible swatch strip with one preview and an Undo action for
applying the preset. Check the minimum Settings size with large icon settings.
The fuller version replaces the "Apply a built-in theme" menu with a row of
live mini-panels (each preset rendered by `OverlayView` at about 0.35 scale);
click one to apply it. The first thing a new user sees in Appearance becomes
the fun part.

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

Start with a “Surprise me” preset in Appearance that previews a random theme
and offers Undo after applying it. A per-session random decoration can reuse
the same choices without adding drawing code or work to the key event path.

### D6 — Boing-ball physics on idle

delight — nice-to-have

Leave the switcher open a few seconds with the Amiga decoration on and let the
ball actually *boing*: drop, bounce off the panel's bottom edge, rotate. The
raster machinery exists; it needs a display link and a sine.

### D7 — Switch-count milestones

delight — nice-to-have

Use the count already on disk (see F4) for a one-time acknowledgment at
1,000, 10,000, and 100,000 switches. Try a brief pixel spark or confetti
outside the fast tap path, with a static equivalent for Reduce Motion.

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

### D12 — Wallpaper tint

delight — nice-to-have

An optional panel tint sampled from the current desktop picture
(`NSWorkspace.desktopImageURL(for:)`, downsampled to a few pixels, cached per
screen), the way Music picks up album art. A calmer cousin of D3.

### D13 — Combo meter

delight — nice-to-have

A tiny lightning bolt in the panel corner that charges with each Tab press and
discharges on commit. Arcade payoff for fast cycling; hidden under Reduce
Motion.

### D14 — Bolt pulse

delight — nice-to-have

The menu-bar bolt flashes once when a switch commits. A quiet confirmation for
tap-toggles that never show the panel.

### D15 — Seasonal easter eggs (opt-in)

delight — nice-to-have

Snow drifting in December, a pumpkin ball at Halloween (reuses the boing
raster). Milestone confetti belongs to D7.

### D16 — Gradient drift

delight — nice-to-have

Let the gradient angle slowly rotate while the panel is open (Vaporwave + CRT
come alive). Off by default, off under Reduce Motion.

### D17 — Haptic detents while cycling

delight — nice-to-have

The scroll haptic already exists; give keyboard cycling the same faint tick on
Force Touch trackpads.

### D18 — Backdrop dim

delight — nice-to-have

Optionally dim the display behind the panel 10–15% while switching,
Stage-Manager style, so the panel pops.

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
An alternative to V2's sliding highlight; pick one.

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
- **Secure Keyboard Entry.** While any app has it on, keyboard events are
  hidden from every event tap, so ⌘-Tab falls through to the system switcher.
  Zap can only say so (the dimmed menu bar icon); it cannot intercept.

Claims checked in November 2026 and found not to be bugs:

- The overlay's app name is centred; a reviewer's misalignment claim didn't
  hold up in the code or the render.
- Settings tab titles are measured in the selected (semibold) weight on
  purpose, so a tab doesn't change width when it's selected.
- The "pause for windows" hint never shows in fallback mode, because fallback
  sessions never receive "?".
- Imported themes are range-checked: `AppearancePreset.apply(to:)` clamps
  every numeric field and falls back to the default for non-finite values.
- `InputModeReporter.mode` is only written on the main thread (the tap's
  run-loop source is on `CFRunLoopGetMain()`), so its subscribers may touch
  AppKit directly.
- Granting Accessibility needs no relaunch: the 2 s input-health check
  promotes Zap to the event tap.
