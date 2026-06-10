# Zap.app

A fast, customizable macOS app switcher — a drop-in replacement for the native
<kbd>⌘</kbd>+<kbd>Tab</kbd> switcher that lets you **exclude apps** you never switch
to, switch **directly to individual windows**, and **customize the appearance** of the switcher.

**Latest release:** v<!-- version -->0.4.0<!-- /version --> · [Download](https://github.com/L-K-M/Zap/releases/latest)

![Screencast](zap-video.gif)

> [!IMPORTANT]
> LLM Disclosure: Much of this code base was written by or with the help of large language models. AI coding agents worked from the [`AGENTS.md`](AGENTS.md) brief in this repo.

## Features

- Intercepts the real <kbd>⌘</kbd>+<kbd>Tab</kbd> (and <kbd>⌘</kbd>+<kbd>⇧</kbd>+<kbd>Tab</kbd> / <kbd>⌘</kbd>+<kbd>`</kbd> to reverse).
- Native-feeling MRU ordering (single tap toggles the two most-recent apps); the order persists across launches.
- **Type to search** while switching — start typing an app's name and the highlight jumps to it. **Number keys** <kbd>1</kbd>–<kbd>9</kbd> switch straight to the Nth app.
- **Spring-loaded switching:** start dragging a file, hit <kbd>⌘</kbd>+<kbd>Tab</kbd> mid-drag, and drop it on an app's icon to open it there — like the Dock, but for every app. (See [Tips](#tips).)
- Per-app exclusions — hide apps you never switch to.
- Dwell on an app to see its windows; switch straight to one with the arrow keys or a click. A long window list scrolls instead of overflowing the panel.
- Optional live preview of each window, laid out as a thumbnail grid (needs Screen Recording permission; off by default).
- **Hold** <kbd>⌘</kbd>+<kbd>Q</kbd> to quit and <kbd>⌘</kbd>+<kbd>H</kbd> to hide the highlighted app without leaving the switcher — a quick tap types into the search instead, so apps like QuickTime stay reachable by name. With a window focused, <kbd>⌘</kbd>+<kbd>W</kbd> closes it.
- Rich appearance: colors, gradients, opacity, icon size, corner radii, retro corner decorations (ZX Spectrum, Apple rainbow, the Amiga boing ball, …), an optional CRT scanline mode, and shareable theme presets — all with a live preview.
- Menu-bar agent (no Dock icon); never appears in its own switcher. The menu-bar icon dims while paused.
- Launch at login via `SMAppService`.
- Fallback to <kbd>⌥</kbd>+<kbd>Tab</kbd> when Accessibility access isn't granted; the Permissions tab reports the trigger that's actually active.

![Screenshot](screenshot.png)

## Build & Run

```bash
# Build
xcodebuild -project Zap.xcodeproj -scheme Zap -configuration Debug build

# Release build
xcodebuild -project Zap.xcodeproj -scheme Zap -configuration Release build

# Run unit tests (pure logic: MRU, exclusions, preferences)
xcodebuild -project Zap.xcodeproj -scheme Zap \
  -destination 'platform=macOS' test
```

For day-to-day development, open `Zap.xcodeproj` in Xcode and run — this makes the
Accessibility permission prompt behave correctly.

## Usage

1. Launch Zap — it appears as a ⌘ icon in the menu bar.
2. Grant Accessibility access when prompted (Permissions tab), then *relaunch.*
3. Use ⌘+Tab as normal. Open **Zap Settings…** from the menu bar to exclude apps
   and adjust colors.

## Tips

- **Spring-loaded switching (drag-and-drop onto an app):** start dragging a file in
  Finder (or anywhere), and *while still dragging* press <kbd>⌘</kbd>+<kbd>Tab</kbd>.
  The switcher appears; drop the file on an app's icon to open it there — drop a
  `.psd` on Photoshop, a folder on Terminal, a link on a browser. Almost nobody knows
  the system switcher can do this; Zap makes it a first-class feature.
- **Type to search:** with the switcher up, just type part of an app's name
  ("term" → Terminal). The highlight jumps to the best match; <kbd>⌫</kbd> edits your
  query and <kbd>Esc</kbd> clears it (a second <kbd>Esc</kbd> dismisses the switcher).
  Every letter types — even <kbd>Q</kbd>/<kbd>W</kbd>/<kbd>H</kbd>, so "QuickTime",
  "Wave", or "Hammerspoon" work; quit and hide answer to a *hold* instead.
- **Number keys:** press <kbd>1</kbd>–<kbd>9</kbd> to jump straight to the Nth app and
  switch — faster than tabbing.
- **In-switcher actions:** hold <kbd>⌘</kbd>+<kbd>Q</kbd> for half a second to quit
  the highlighted app, hold <kbd>⌘</kbd>+<kbd>H</kbd> to hide it (or un-hide) — a
  quick tap types into the search instead — and with a window selected,
  <kbd>⌘</kbd>+<kbd>W</kbd> closes it.
- **Themes:** in **Appearance**, apply a built-in theme (Classic, ZX Night, Vaporwave,
  Amiga) or **Export…** your look to a small `.json` file to share and **Import…**
  later.

## Troubleshooting

### Zap asks for Accessibility access on every launch

macOS ties an Accessibility grant to the app's **code signature**. A default debug
build is ad-hoc signed ("Sign to Run Locally"), so **every rebuild produces a new
signature** — macOS then treats it as a different app, `AXIsProcessTrusted()`
returns `false`, and Zap prompts again (falling back to ⌥-Tab in the meantime).

**Reset the permission and grant from scratch:**

```bash
tccutil reset Accessibility com.zapapp.Zap
```

Then open **System Settings → Privacy & Security → Accessibility**, remove any
leftover/duplicate **Zap** rows with the **–** button, and relaunch Zap to grant
again. (To clear grants for *all* apps as a last resort: `tccutil reset Accessibility`.)

**Make the grant stick across rebuilds** by signing with a stable identity instead
of ad-hoc. In the Zap target's build settings (Signing & Capabilities):

- Set `DEVELOPMENT_TEAM` to your Apple Developer Team ID.
- Use Automatic signing with `CODE_SIGN_IDENTITY = "Apple Development"`.

A real Apple Development certificate produces a stable *designated requirement*, so
the grant persists. Also launch the built `Zap.app` from a **fixed path** (not a
copy), since TCC keys partly on location for ad-hoc-signed apps.
