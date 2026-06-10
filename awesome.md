# Zap — Code Review & Ideas

A living review of the codebase (June 2026): bugs, general issues, missing
features, and ideas — from the practical to the delightful. Entries are removed
here as they ship.

Since the original v1.5.1 review, two batches have landed. First, a round of
fixes and native-switcher parity: the ⌘W preview wipe, the fallback-mode
permission nag, offline-name mangling, ⌘H hide, ←/→ app cycling, persisted MRU
order, and the dimmed paused menu-bar icon. Then the whole *novel / delightful*
batch: type-to-search and number-key jumps, appearance presets (JSON
export/import + built-in themes), CRT mode and the Amiga boing-ball decoration,
the switch-count tally in an About tab, optional scroll haptics, and the README
write-up of spring-loaded drag-and-drop. The duplicated icon-row layout
constants were also unified into a shared `IconRowMetrics`.

What remains below is the gap between "good" and "delightful". The codebase is in
genuinely good shape: small, well-factored modules, pure logic extracted for unit
testing, careful comments that explain *why* (the activation hand-off dance, the
event-tap re-enable, the layout retry for the "small square" glitch).

---

## 1. Bugs

### 1.1 ⌘Q / ⌘W / ⌘H use position-based key codes — wrong keys on non-QWERTY layouts

`KeyCode.q = 0x0C`, `.w = 0x0D`, and `.h = 0x04` are *positions*, not characters.
On AZERTY, the key at position 0x0C types `A`; a French user pressing ⌘A mid-switch
quits the selected app, while ⌘Q does nothing. The newer type-to-search path already
reads characters layout-aware (`EventTapMonitor.typedCharacter(for:)` clears the
modifiers and calls `keyboardGetUnicodeString`), so the clean fix is to route the
action keys through the same translation (or `UCKeyTranslate` /
`TISCopyCurrentKeyboardInputSource`) before matching. Worth doing — AltTab went
through this exact bug — but it needs careful testing across layouts.

- `Zap/Hotkey/KeyCodes.swift:9-12`, `Zap/Hotkey/EventTapMonitor.swift`

### 1.2 An update alert can fight an active switch session

`UpdateChecker` can pop a modal alert (launch check) while a ⌘-Tab session is live;
the event tap keeps swallowing keys while `isSwitching()` and a modal run loop is
spinning underneath. Hard to hit in practice (the check fires once at launch), but
the clean fix is to defer presentation while a session is active.

- `Zap/Updates/UpdateChecker.swift:124-152`

---

## 2. General issues

### 2.1 No way to cancel a session in fallback mode

Without the event tap there's no Esc handling, and the auto-commit timer always
fires — the only "cancel" is clicking outside (if that preference is on) or cycling
back to the current app. Inherent to Carbon hotkeys, but worth documenting in the
Settings caption for the fallback toggle.

### 2.2 `AppearanceView.preview` rebuilds its model every render

The computed `preview` property creates a fresh `OverlayModel` on each body
evaluation. Harmless at this scale, but a `@StateObject` would be idiomatic.

- `Zap/Settings/AppearanceView.swift` (the `preview` property)

### 2.3 Session app list is a snapshot

Apps launched or quit (outside Zap's own ⌘Q path) mid-session aren't reflected
until the next session. Already acknowledged in `ISSUES.md`; commit safely no-ops
on a vanished app, so this stays a deliberate trade-off for a stable hot path.

---

## 3. Missing features (native-switcher parity)

### 3.1 Indicate hidden / windowless apps

Natively you can't tell which apps are hidden (⌘H) — Zap could do better: a subtle
badge or reduced opacity for hidden apps, and/or a window-count badge per icon.
`NSRunningApplication.isHidden` is already consulted at activation time; carrying
it into `AppInfo` is easy. (Pairs nicely with the existing ⌘H hide.)

### 3.2 Configurable trigger hotkey

The fallback is hardwired to ⌥-Tab and the primary to ⌘-Tab. Power users will want
e.g. ⌥-Space or a hyper-key trigger. Needs a key-recorder control in Settings;
medium effort.

---

## 4. Decoration ideas (backlog — none implemented yet)

Brainstormed after the boing-ball work. `DecorationKind` currently knows
`stripes` and `ball`; several of these want new kinds — `background`, `border`,
edge strip, pixel `sprite` — and the sprite family can reuse the raster
machinery `BoingBallDecoration` already has (fixed-resolution bitmap,
nearest-neighbor upscale, cached `CGImage`). Like the existing ZX/Apple/Amiga
styles, most are affectionate nods to trademarked designs — the same homage
spirit, and the same bucket.

### 4.1 Companions to existing styles

- **Boing grid** — the original demo's magenta wireframe grid, drawn faintly
  behind the whole panel. Pairs with the ball, so the Amiga preset becomes a
  full diorama. (Background kind.)
- **Synthwave sun** — a striped setting-sun semicircle in a corner; the natural
  partner for the Vaporwave stripes + CRT mode.
- **Spectrum loading border** — alternating cyan/yellow bars around the panel's
  edge, the tape-loading screen every 80s kid stared at. Pairs with the ZX
  stripes. (Border kind — one clipped stroke.)

### 4.2 Pixel sprites (data-driven bitmaps over the boing-ball raster path)

- **Tetromino stack** — a few classic pieces snugged into the top corner as if
  mid-fall. Blocks stacking into a corner is exactly what tetrominoes do;
  the strongest candidate of the lot.
- **Space invader** — the 11×8 alien, crisp chunky pixels in the corner.
- **Clarus the dogcow** — Susan Kare deep cut for the Mac faithful. Moof.

### 4.3 More machine homages

- **C64** — dark-blue panel with the boot screen's lighter-blue inner border;
  optionally a tiny `READY.` with a blinking block cursor.
- **Atari woodgrain** — a 2600-style woodgrain strip along the panel's bottom
  edge. Ridiculous in the best way.
- **Classic Mac title bar** — the System 7 six-pinstripe title bar with a close
  box across the panel top; makes the switcher read as a vintage window.
- **IBM stripes** — the eight-bar blue monogram stack in a corner.

### 4.4 Pure delight

- **Googly eyes (xeyes)** — two eyes in the corner whose pupils *track the
  highlighted icon*. The only one needing model wiring (the selection index)
  rather than just preferences; also the one people would screenshot.
- **"Surprise me"** — a meta-style that picks a random decoration per session.
  Zero drawing code, instant charm.

---

## 5. Test gaps (carried forward)

- Reverse-cycling / commit / cancel still depend on AppKit and remain untested
  (acknowledged in `ISSUES.md`).
- `WindowEnumerator` AX paths are inherently un-unit-testable; the pure
  `offSpaceWindowInfo(from:pid:)` extraction pattern could be applied to more of it.
- New pure logic ships with tests: MRU seeding, type-to-search matching
  (`SwitcherController.bestMatchIndex`), appearance-preset apply/validation, and the
  switch-count midnight rollover (`Preferences.incrementedSwitchCounts`). The CRT and
  boing-ball rendering, like the rest of the SwiftUI overlay, is verified by eye.
