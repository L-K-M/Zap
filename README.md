# Zap

A fast, customizable macOS app switcher — a drop-in replacement for the native
<kbd>⌘</kbd>+<kbd>Tab</kbd> switcher that lets you **exclude apps** you never switch
to and **customize the colors** of the switcher.

See [`PLAN.md`](PLAN.md) for the full design and [`AGENTS.md`](AGENTS.md) for
contributor/agent guidance.

## Features

- Intercepts the real <kbd>⌘</kbd>+<kbd>Tab</kbd> (and <kbd>⌘</kbd>+<kbd>⇧</kbd>+<kbd>Tab</kbd> / <kbd>⌘</kbd>+<kbd>`</kbd> to reverse).
- Native-feeling MRU ordering (single tap toggles the two most-recent apps).
- Per-app exclusions — hide apps you never switch to.
- Customizable colors, opacity, icon size, and corner radius with a live preview.
- Menu-bar agent (no Dock icon); never appears in its own switcher.
- Launch at login via `SMAppService`.
- Graceful fallback to <kbd>⌥</kbd>+<kbd>Tab</kbd> when Accessibility access isn't granted.

## Build & Run

```bash
# Build
xcodebuild -project Zap.xcodeproj -scheme Zap -configuration Debug build

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
