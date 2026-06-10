# Zap — Code Review & Ideas

A full review of the codebase as of v1.5.1 (June 2026): bugs, general issues,
missing features, and ideas — from the practical to the delightful. Entries marked
**→ implementing** are being addressed in follow-up PRs from this review cycle;
everything else is recorded here for future work.

The codebase is in genuinely good shape: small, well-factored modules, pure logic
extracted for unit testing, careful comments that explain *why* (the activation
hand-off dance, the event-tap re-enable, the layout retry for the "small square"
glitch). The notes below are the gap between "good" and "delightful".

---

## 1. Bugs

### 1.1 Closing a window with ⌘W wipes all remaining previews — **→ implementing**

`SwitcherController.closeFocusedWindow()` calls `overlay.setWindows(...)`, which
resets `model.windowThumbnails = [:]` — but unlike `revealWindows()`, it never calls
`loadThumbnails()` again. Close one window in the preview grid and every *other*
window's thumbnail reverts to the placeholder glyph for the rest of the session.
The fix is one line (re-kick `loadThumbnails()`); the `WindowThumbnailProvider`
cache (5 s TTL) makes the reload essentially free.

- `Zap/Switcher/SwitcherController.swift:588-608`

### 1.2 Accessibility nag on every launch even when the user chose the fallback — **→ implementing**

`AppDelegate.promptForAccessibilityIfNeeded()` prompts whenever the event tap isn't
active. But `preferences.useAlternateHotkey == true` means the user *deliberately*
forced the ⌥-Tab fallback — they shouldn't be nagged for a permission Zap won't use.

- `Zap/AppDelegate.swift:123-127`

### 1.3 Offline-app display names mangled by blanket `.app` replacement — **→ implementing**

`ExclusionsView.displayName(forBundleID:)` does
`replacingOccurrences(of: ".app", with: "")`, which strips *every* occurrence of
the substring, not just the trailing extension — an app named e.g. `Wh.appy.app`
would render as `Why`. Strip only a trailing `.app` path extension instead.

- `Zap/Settings/ExclusionsView.swift:73-77`

### 1.4 README typo

"switch **directoy do** individual screens" → "switch **directly to** individual
windows" (it also says "screens" where the feature described is windows).
**→ implementing** (fixed alongside this document).

- `README.md:5`

### 1.5 ⌘Q / ⌘W use position-based key codes — wrong keys on non-QWERTY layouts

`KeyCode.q = 0x0C` and `KeyCode.w = 0x0D` are *positions*, not characters. On
AZERTY, the key at position 0x0C types `A`; a French user pressing ⌘A mid-switch
quits the selected app, while ⌘Q does nothing. Proper fix: translate the event's
key code through the current keyboard layout (`UCKeyTranslate` /
`TISCopyCurrentKeyboardInputSource`) before matching. Not implementing now — it
needs careful testing across layouts — but worth doing; AltTab went through this
exact bug.

- `Zap/Hotkey/KeyCodes.swift:8-9`, `Zap/Hotkey/EventTapMonitor.swift:149-155`

### 1.6 An update alert can fight an active switch session

`UpdateChecker` can pop a modal alert (launch check) while a ⌘-Tab session is live;
the event tap keeps swallowing keys while `isSwitching()` and a modal run loop is
spinning underneath. Hard to hit in practice (the check fires once at launch), but
the clean fix is to defer presentation while a session is active.

- `Zap/Updates/UpdateChecker.swift:124-152`

---

## 2. General issues

### 2.1 Duplicated icon-row layout constants

`OverlayWindowController.iconRowGeometry()` hardcodes `cellWidth = iconSize + 16`
and `spacing = 12`, mirroring `OverlayView` ("matches OverlayView.iconSpacing").
The geometry struct already exists (`IconRowGeometry`) — the *inputs* should live
in one shared place (e.g. an `IconRowMetrics` enum like `WindowGridMetrics`), so
the two can't drift.

- `Zap/Overlay/OverlayWindowController.swift:320-327`, `Zap/Overlay/OverlayView.swift:10,74`

### 2.2 No way to cancel a session in fallback mode

Without the event tap there's no Esc handling, and the auto-commit timer always
fires — the only "cancel" is clicking outside (if that preference is on) or cycling
back to the current app. Inherent to Carbon hotkeys, but worth documenting in the
Settings caption for the fallback toggle.

### 2.3 `AppearanceView.preview` rebuilds its model every render

The computed `preview` property creates a fresh `OverlayModel` on each body
evaluation. Harmless at this scale, but a `@StateObject` would be idiomatic.

- `Zap/Settings/AppearanceView.swift:74-80`

### 2.4 Session app list is a snapshot

Apps launched or quit (outside Zap's own ⌘Q path) mid-session aren't reflected
until the next session. Already acknowledged in `ISSUES.md`; commit safely no-ops
on a vanished app, so this stays a deliberate trade-off for a stable hot path.

---

## 3. Missing features (native-switcher parity)

### 3.1 ⌘H — hide the selected app — **→ implementing**

The native switcher hides the selected app with H (and un-hides a hidden one).
Zap swallows the key and does nothing — and the original PLAN.md even promised it.
Quit's sibling; cheap to add (`NSRunningApplication.hide()`/`unhide()`), no AX
permissions beyond what's already granted.

### 3.2 ← / → to move the app selection — **→ implementing**

Natively, arrow keys move the highlight. In Zap, ←/→ only work inside the window
*preview grid*; with the app row focused they're swallowed dead keys. When
`windowSelectedIndex == nil`, ←/→ should advance/retreat the app selection.

### 3.3 Persist MRU order across launches — **→ implementing**

On a cold launch only the frontmost app is known; everything else sits in
`NSWorkspace.runningApplications` order, so the first ⌘-Tab after login often
highlights the wrong "previous" app. There's no API for the system's own MRU, but
Zap can persist *its own* (a small capped array of bundle IDs in `UserDefaults`)
and seed the tracker from it at launch — yesterday's order is a far better prior
than process-table order.

- `Zap/Switcher/MRUTracker.swift`, `Zap/Switcher/AppListProvider.swift:62-67`

### 3.4 Indicate hidden / windowless apps

Natively you can't tell which apps are hidden (⌘H) — Zap could do better: a subtle
badge or reduced opacity for hidden apps, and/or a window-count badge per icon.
`NSRunningApplication.isHidden` is already consulted at activation time; carrying
it into `AppInfo` is easy. (Pairs nicely with 3.1.)

### 3.5 Configurable trigger hotkey

The fallback is hardwired to ⌥-Tab and the primary to ⌘-Tab. Power users will want
e.g. ⌥-Space or a hyper-key trigger. Needs a key-recorder control in Settings;
medium effort.

---

## 4. Novel / delightful / quirky ideas

### 4.1 Dim the menu-bar icon while paused — **→ implementing**

"Pause Zap" currently gives no visual feedback; the ⌘⚡ icon looks identical while
inert. `statusItem.button.appearsDisabled = true` is a one-liner that makes the
state legible at a glance.

### 4.2 Type-to-filter while switching

Hold ⌘ and type letters: the row filters/jumps to apps whose names match
("te" → Terminal/TextEdit). The event tap already swallows those keys mid-session —
they're currently wasted input. This is the kind of feature that makes people
switch switchers. (Interacts with 1.5 — needs character-level, layout-aware key
translation, so do that first.)

### 4.3 Number keys jump-and-commit

While the overlay is up, pressing 1–9 switches straight to the Nth app — one
keystroke beats four Tab presses. Cheap; the digits are dead keys today.

### 4.4 Appearance presets — export/import/share themes

The appearance system (colors, gradient + angle, opacity, radii, retro corner
decorations) is unusually rich. Let users save named presets and share them as
small JSON files, and ship two or three built-ins ("Classic", "ZX Night",
"Vaporwave"). Most of the plumbing exists (`Preferences.Default`,
`resetDefaults()` already enumerates every appearance key).

### 4.5 CRT mode

The ZX Spectrum / Apple-rainbow corner decorations are crying out for an optional
scanline + slight-bloom overlay on the panel. Pure `Canvas` shader fun, zero risk,
maximum charm. (A "boing ball" decoration for the Amiga fans would complete the
set.)

### 4.6 Spring-loaded switching for drag-and-drop — document it!

Dropping files onto an app icon in the overlay *already works*
(`onDropFiles`/`openFiles`). What's missing is the README selling it: start
dragging a file, hit ⌘-Tab while dragging, drop on Safari's icon. Almost nobody
knows the native switcher can do this — Zap supporting it is a headline feature
hiding in the code.

### 4.7 Switch-count Easter egg

A tiny "switches today: 1,024" line in the Settings About area. Zero-cost
telemetry-free fun (a counter in `UserDefaults`), and the kind of detail people
screenshot.

### 4.8 Haptic tick when scrolling the icon row

The icon row already supports continuous trackpad scrolling;
`NSHapticFeedbackManager` could give a faint `alignment` tick as the selection
crosses each icon. Subtle, native-feeling, off by default.

---

## 5. Test gaps (carried forward)

- Reverse-cycling / commit / cancel still depend on AppKit and remain untested
  (acknowledged in `ISSUES.md`).
- `WindowEnumerator` AX paths are inherently un-unit-testable; the pure
  `offSpaceWindowInfo(from:pid:)` extraction pattern could be applied to more of it.
- New pure logic added by this cycle's PRs (MRU seeding) ships with tests.
