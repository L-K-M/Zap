# Zap — A Fast, Customizable macOS App Switcher

A lightweight replacement for the built-in <kbd>⌘</kbd>+<kbd>Tab</kbd> switcher. It
looks and behaves like the native switcher, but lets you **exclude apps** you never
switch to and **customize basic colors**.

---

## 1. Goals & Non-Goals

### Goals
- Visually and behaviorally mimic the native macOS app switcher.
- Trigger on <kbd>⌘</kbd>+<kbd>Tab</kbd> (and <kbd>⌘</kbd>+<kbd>⇧</kbd>+<kbd>Tab</kbd> to cycle backward).
- Exclude a user-defined set of apps from the switcher.
- Customize a few colors (background, selection highlight, optional text/label).
- Be fast: appear instantly on keypress, no perceptible lag.
- Reveal the selected app's windows after a configurable dwell, and let the user
  switch directly to a window with <kbd>↑</kbd>/<kbd>↓</kbd> or a click.
- Optionally show a small live preview of each window in that list (requires the
  separate Screen Recording permission; off by default).

### Non-Goals (v1)
- Per-app actions beyond activate/quit/hide.
- App Store distribution (see §9 — the event tap makes this impractical).
- Themes/skins beyond a handful of color settings.

---

## 2. High-Level Architecture

A background **menu-bar / agent app** (`LSUIElement = true`, no Dock icon) so it never
appears in its own switcher.

```
┌─────────────────────────────────────────────────────────┐
│ Zap (LSUIElement agent app)                              │
│                                                          │
│  ┌────────────────┐   ┌───────────────────────────────┐  │
│  │ HotkeyMonitor  │   │ AppListProvider               │  │
│  │ (CGEventTap)   │   │ - NSWorkspace running apps    │  │
│  │ - intercept    │──▶│ - MRU ordering                │  │
│  │   ⌘Tab / Shift │   │ - exclusion filter            │  │
│  │ - detect ⌘ up  │   └───────────────────────────────┘  │
│  └───────┬────────┘                  │                   │
│          │                           ▼                   │
│          │                ┌────────────────────┐         │
│          └───────────────▶│ SwitcherController │         │
│                           │ - selection state  │         │
│                           │ - show/hide overlay│         │
│                           └─────────┬──────────┘         │
│                                     ▼                     │
│              ┌──────────────────────────────────┐        │
│              │ OverlayWindow (borderless NSWindow│        │
│              │  / SwiftUI) — icons + highlight   │        │
│              └──────────────────────────────────┘        │
│                                                          │
│  ┌────────────────┐   ┌───────────────────────────────┐  │
│  │ StatusItem     │   │ Settings (SwiftUI window)     │  │
│  │ (menu bar)     │──▶│ - Exclusions, Colors, Perms   │  │
│  └────────────────┘   └───────────────────────────────┘  │
│                                  │                       │
│                                  ▼                       │
│                       ┌────────────────────┐             │
│                       │ Preferences store  │             │
│                       │ (UserDefaults)     │             │
│                       └────────────────────┘             │
└─────────────────────────────────────────────────────────┘
```

**Tech stack:** Swift, SwiftUI for Settings + overlay rendering, AppKit for windowing,
`NSWorkspace`, and a low-level `CGEventTap` for the hotkey. Targets macOS 13+.

---

## 3. The Hard Part: Intercepting ⌘+Tab

The native ⌘+Tab is owned by the system. There is no public API to "reskin" it, so we
must **intercept the key event and suppress the system switcher**.

### Approach: `CGEventTap`
- Install a session-level event tap (`CGEventTapCreate`) listening for `keyDown`
  and `flagsChanged`.
- When we see <kbd>Tab</kbd> (keycode `48`) with **only** the Command flag active
  (plus optional Shift), we **consume** the event (return `nil` from the callback) so
  the system switcher never sees it, and drive our own switcher instead. Combinations
  that also hold Control, Option, or Fn are passed through untouched.
- Track the Command modifier via `flagsChanged`. When Command is **released** while the
  overlay is visible, **commit** the current selection (activate that app) and hide.
- Subsequent <kbd>Tab</kbd> presses while Command is still held advance the selection;
  <kbd>⇧</kbd>+<kbd>Tab</kbd> moves backward.

> **Requires Accessibility permission** (`AXIsProcessTrusted`). The app must be granted
> access in *System Settings → Privacy & Security → Accessibility*. We can't tap keys
> without it. The tap must be re-enabled if the system disables it
> (`kCGEventTapDisabledByTimeout`).

### Key handling while overlay is visible
| Key                        | Action                                  |
|----------------------------|-----------------------------------------|
| <kbd>Tab</kbd>             | Next app                                |
| <kbd>⇧</kbd>+<kbd>Tab</kbd> | Previous app                            |
| <kbd>`</kbd> (backtick)    | Previous app — only while switching (matches native) |
| Release <kbd>⌘</kbd>       | Activate selected app, hide overlay     |
| <kbd>Esc</kbd>            | Cancel, hide overlay, no switch         |
| <kbd>Q</kbd>               | Quit selected app                       |
| <kbd>H</kbd>               | Hide selected app (un-hide if already hidden) |
| <kbd>W</kbd>               | Close focused window (in the window list) |
| <kbd>↑</kbd> / <kbd>↓</kbd> | Move through the selected app's windows |
| <kbd>←</kbd> / <kbd>→</kbd> | Move the app selection; within the preview grid, move along the row |
| Mouse hover / click        | Move selection / pick app or window     |

### Fallback / coexistence
- If Accessibility is **not** granted, fall back to a configurable alternate hotkey
  (e.g. <kbd>⌥</kbd>+<kbd>Tab</kbd>) registered via Carbon `RegisterEventHotKey`, which
  needs no special permission — and prompt the user to grant access for the real ⌘+Tab.
- Optionally suggest the user disable native ⌘+Tab is **not** required — our tap
  suppresses it while Zap is active.

### Window previews (optional)
- Each window can show a small still capture. Disabled by default; enabling it
  requires the separate **Screen Recording** permission
  (`CGPreflightScreenCaptureAccess` / `CGRequestScreenCaptureAccess`).
- **Layout:** with previews **on**, the windows are shown as a roughly-square
  **grid** of thumbnail tiles (each a preview above a one-line title); with
  previews **off**, as a single-column list of titles. The grid's column count is a
  pure function of the window count and available width (`WindowGridGeometry`),
  shared with the controller so arrow-key navigation is grid-aware. Either form
  **scrolls vertically** once it would grow taller than the room left on screen. The
  panel's top edge stays fixed and the list grows only *downward*: the height cap
  (`model.maxPanelHeight`, set in `layout` via `maxPanelHeight(anchorTop:…)`) is the
  space from that top down to the bottom of the screen, so the list reaches the
  bottom and then scrolls instead of the panel shifting up to stay on-screen.
- The `CGWindowID` for an AX window element is resolved via the private
  `_AXUIElementGetWindow` SPI (no public bridge exists). Treated as best-effort —
  a `nil` ID just means "no preview", never a failure.
- Capture runs off the hot path in `WindowThumbnailProvider` (an `actor`):
  ScreenCaptureKit's `SCScreenshotManager` on macOS 14+, falling back to the
  deprecated `CGWindowListCreateImage` on macOS 13. Results are downscaled and
  held in a bounded, TTL-bounded `LRUImageCache`. Minimized/off-screen windows
  have no backing store and keep the placeholder glyph.

---

## 4. App List, Ordering & Exclusions

### Source of apps
- `NSWorkspace.shared.runningApplications`, filtered to
  `activationPolicy == .regular` (apps that normally appear in the switcher/Dock),
  with Zap itself explicitly excluded because Settings temporarily makes Zap a
  regular app.
- Each gives an `NSRunningApplication`: `bundleIdentifier`, `localizedName`, `icon`,
  `processIdentifier`, and activation APIs.

### Most-Recently-Used (MRU) ordering
- The native switcher lists apps in MRU order with the previously-active app
  pre-selected (so a quick ⌘+Tab tap toggles between the two most recent apps).
- Maintain our own MRU list by observing
  `NSWorkspace.didActivateApplicationNotification` and moving the activated app to the
  front, ignoring Zap's own activations while Settings is open. The order is persisted
  (a small capped array of bundle IDs in `UserDefaults`) and seeds the tracker on the
  next launch.
- On show: order = MRU list; default selection = index `1` (second item) so a single
  tap switches to the last app, matching native feel. When the frontmost app is
  *excluded* it is filtered out, so the default selection becomes index `0` instead
  (the previous visible app), preserving the toggle feel.
- **Known limitation:** there is no public API for the system's own MRU order, so on a
  cold launch Zap starts from its *persisted* order from the previous session (with the
  current frontmost app promoted to the top). Switches made while Zap wasn't running
  are invisible to it, so the order may briefly lag reality until the user activates
  apps again (which our notification observer then records).

### Exclusions
- Store a `Set<String>` of excluded **bundle identifiers** in `UserDefaults`.
- Filter excluded apps out of the displayed list (they remain running and usable, just
  hidden from Zap).
- Settings UI lists currently running + previously seen apps with checkboxes.

---

## 5. The Overlay UI

A borderless, transparent, floating window mimicking the native look.

- **Window:** `NSWindow` with `styleMask = .borderless`, `isOpaque = false`,
  `backgroundColor = .clear`, `level = .popUpMenu` (above normal windows),
  `collectionBehavior` including `.canJoinAllSpaces` and `.stationary` so it shows on
  any Space. Ignores mouse events except when hover-selection is enabled.
- **Content (SwiftUI hosted in an `NSHostingView`):**
  - Rounded-rect panel with an `NSVisualEffectView` (blur) background, tinted by the
    user's chosen background color/opacity. Optionally a gradient: the tint runs from
    the background color to a second color at any angle (set with a 360° dial). The
    gradient line is pinned to a fixed top-center reference rect (name + icon row) and
    converted to unit points against the current panel size, so it does **not**
    restretch when the window list grows the panel — the always-visible icon row keeps
    a constant appearance at every angle.
  - Optional retro corner **decoration** (e.g. ZX Spectrum diagonal rainbow stripes)
    drawn in the top-left or top-right corner, clipped to the panel's rounded edge.
  - Horizontal row of app icons (~64–128px), wrapping or scrolling if many.
  - Selection highlight: rounded rectangle behind the selected icon using the user's
    highlight color.
  - Selected app's name shown as a label below/above the row (native shows name on top).
- **Positioning:** Centered on the screen with the active mouse/key focus
  (`NSScreen.main` or screen under cursor).
- **Show/hide:** No fade by default for speed; optional short (~80ms) fade as a setting.
  Native switcher shows after a brief hold — we can replicate the small delay so a quick
  tap-and-release doesn't flash the UI (configurable).

---

## 6. Customization (Colors)

Stored in `UserDefaults`, applied live to the overlay. v1 settings:

| Setting                | Type            | Default                      |
|------------------------|-----------------|------------------------------|
| Background color       | Color + opacity | System dark translucent      |
| Selection highlight    | Color + opacity | System accent / light gray   |
| Label text color       | Color           | Primary label color          |
| Icon size              | Slider (48–128) | 80                           |
| Corner radius          | Slider          | 18                           |
| Show app name label    | Toggle          | On                           |
| Show delay before UI   | Slider (0–250ms)| ~150ms                       |

Colors persisted as hex/`Codable` wrappers around `NSColor`. A live preview in Settings
shows the overlay with current values.

---

## 7. Settings Window

A standard SwiftUI window opened from the menu-bar item, with tabs:

1. **General** — launch at login (`SMAppService`), show-delay, window dwell +
   previews toggle, alternate hotkey.
2. **Exclusions** — searchable list of apps with include/exclude toggles.
3. **Appearance** — the color/size controls from §6 with live preview.
4. **Permissions** — Accessibility status (required) and Screen Recording status
   (optional, for window previews) + buttons to open the relevant System Settings
   panes; guidance text.

Menu-bar `NSStatusItem` menu: *Settings…*, *Pause Zap*, *Quit*.

---

## 8. Persistence

- `UserDefaults` (small, simple): excluded bundle IDs, color/appearance settings,
  alternate hotkey, launch-at-login flag, show delay, and the MRU order (a capped
  array of bundle IDs, so a cold launch starts from the previous session's order).
- No database needed.

---

## 9. Permissions, Signing & Distribution

- **Accessibility permission** is mandatory for the ⌘+Tab event tap. Onboarding must
  detect and request it (`AXIsProcessTrustedWithOptions` with the prompt option).
- **`LSUIElement = true`** in Info.plist so Zap has no Dock icon and never lists itself.
- **Launch at login** via `SMAppService.mainApp` (macOS 13+).
- **Distribution:** Developer ID signing + notarization for direct download. The App
  Store is impractical because of the global event tap / Accessibility usage.
- **Hardened runtime** enabled; no special entitlements beyond what the tap needs
  (Accessibility is a user-granted permission, not an entitlement).

---

## 10. Project Structure (proposed)

```
Zap/
├── Zap.xcodeproj
├── Zap/
│   ├── ZapApp.swift            # @main
│   ├── AppDelegate.swift       # app delegate, status item
│   ├── Hotkey/
│   │   ├── EventTapMonitor.swift
│   │   ├── CarbonHotkey.swift   # fallback alt-hotkey
│   │   ├── AccessibilityAuthorizer.swift
│   │   ├── ScreenRecordingAuthorizer.swift  # gates window previews
│   │   └── KeyCodes.swift
│   ├── Switcher/
│   │   ├── SwitcherController.swift
│   │   ├── AppListProvider.swift
│   │   ├── MRUTracker.swift
│   │   ├── WindowEnumerator.swift
│   │   ├── WindowThumbnailProvider.swift    # async window capture (actor)
│   │   ├── LRUImageCache.swift              # bounded TTL preview cache
│   │   └── InputModeReporter.swift
│   ├── Overlay/
│   │   ├── OverlayWindowController.swift
│   │   ├── OverlayModel.swift
│   │   ├── OverlayView.swift     # SwiftUI
│   │   └── VisualEffectView.swift
│   ├── Settings/
│   │   ├── SettingsWindowController.swift
│   │   ├── SettingsView.swift
│   │   ├── GeneralView.swift
│   │   ├── ExclusionsView.swift
│   │   ├── AppearanceView.swift
│   │   └── PermissionsView.swift
│   ├── Updates/
│   │   ├── UpdateChecker.swift   # GitHub release check + update alert (reusable)
│   │   ├── GitHubReleaseClient.swift
│   │   ├── GitHubRelease.swift
│   │   ├── UpdateDownloader.swift # downloads an asset to ~/Downloads
│   │   └── SemanticVersion.swift
│   ├── Model/
│   │   ├── Preferences.swift     # UserDefaults wrapper
│   │   ├── AppInfo.swift
│   │   └── ColorHex.swift
│   └── Resources/
│       └── Assets.xcassets      # Info.plist is generated
└── README.md
```

---

## 11. Implementation Phases / Milestones

> **Status:** Phases 1–9 implemented in the initial build. Remaining work is
> hardware/GUI verification (multi-monitor, Spaces, fullscreen) and release
> signing/notarization, which require a real macOS session.

1. **Skeleton** ✅ — Xcode project, `LSUIElement` agent app, menu-bar status item,
   Settings window.
2. **App listing** ✅ — `AppListProvider` + `MRUTracker`.
3. **Overlay** ✅ — borderless window rendering the icon row + highlight.
4. **Event tap** ✅ — intercept ⌘+Tab, suppress system switcher, drive selection,
   commit on ⌘ release; Accessibility permission flow + tap re-enable.
5. **Activation** ✅ — cooperatively yield to and activate the selected app; MRU
   toggle feel.
6. **Exclusions** ✅ — Settings UI + `UserDefaults` filtering.
7. **Appearance** ✅ — color/size settings + live preview applied to overlay.
8. **Polish** ✅ — show-delay, reverse cycling, Esc cancel, launch-at-login,
   quit-selected, target-screen selection.
9. **Hardening & release** ☐ — sign, notarize, onboarding copy, app icon art.

---

## 12. Key Risks & Edge Cases

- **Accessibility denied** → fall back to alt-hotkey + clear prompt; core feature
  degraded but app still usable.
- **Event tap disabled by timeout** → listen for `kCGEventTapDisabledByTimeout` and
  re-enable.
- **Fullscreen / per-Space apps** → ensure overlay `collectionBehavior` shows it
  everywhere; `activate` may switch Spaces (matches native).
- **Apps launching/quitting mid-switch** → guard against stale `pid`/bundle IDs.
- **Multiple monitors** → show overlay on the active screen.
- **Performance** → pre-warm overlay window; cache icons; avoid rebuilding the whole
  view on each Tab (only move the highlight).
- **Conflicts with other switcher utilities** (e.g. user already remapped ⌘+Tab).
