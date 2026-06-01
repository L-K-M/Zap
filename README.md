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
