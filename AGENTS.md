# AGENTS.md

Guidance for AI coding agents working in the **Zap** repository.

## What Zap Is

Zap is a fast, customizable macOS app switcher — a replacement for the native
<kbd>⌘</kbd>+<kbd>Tab</kbd> switcher that adds app exclusions and basic color
customization. See `PLAN.md` for the full design and milestones.

## Tech Stack

- **Language:** Swift (latest stable).
- **UI:** SwiftUI for Settings and the overlay content; AppKit for windowing
  (`NSWindow`, `NSStatusItem`, `NSVisualEffectView`).
- **System APIs:** `NSWorkspace`, `CGEventTap` (hotkey interception), Carbon
  `RegisterEventHotKey` (fallback hotkey), `SMAppService` (launch at login).
- **Persistence:** `UserDefaults`.
- **Min target:** macOS 13 (Ventura) or newer.
- **App type:** Menu-bar agent (`LSUIElement = true`, no Dock icon).

## Build & Run

The Xcode project (`Zap.xcodeproj`) uses Xcode 16 file-system–synchronized groups,
so new files added under `Zap/` or `ZapTests/` are picked up automatically — no
`project.pbxproj` edits needed. **Requires Xcode 16+.**

```bash
# Build
xcodebuild -project Zap.xcodeproj -scheme Zap -configuration Debug build

# Run tests
xcodebuild -project Zap.xcodeproj -scheme Zap -destination 'platform=macOS' test
```

Prefer building/running from Xcode during development for permission prompts.

## Conventions

- Follow standard Swift API Design Guidelines; use Swift naming conventions.
- Keep modules aligned with the structure in `PLAN.md §10` (Hotkey, Switcher, Overlay,
  Settings, Model).
- One type per file; file name matches the primary type.
- Use `// MARK:` to organize sections.
- Avoid force-unwraps outside of tests; handle optional `NSRunningApplication` fields.
- Keep the switcher hot path allocation-light; only move the selection highlight on
  <kbd>Tab</kbd>, do not rebuild the whole view.

## Critical Constraints

- **Accessibility permission is required** for the ⌘+Tab event tap. Always handle the
  not-granted case gracefully and re-enable the tap on
  `kCGEventTapDisabledByTimeout`.
- **Never let Zap appear in its own switcher** — keep `LSUIElement = true`.
- The overlay window must show across all Spaces and over fullscreen apps
  (`collectionBehavior`: `.canJoinAllSpaces`, `.stationary`, `.fullScreenAuxiliary`).
- Don't break the native MRU "tap to toggle last two apps" feel.

## Testing Notes

- Event-tap and overlay behavior need a real macOS GUI session; they can't be fully
  unit-tested in CI. Unit-test pure logic: MRU ordering, exclusion filtering,
  preferences encoding/decoding.
- Manually verify: multi-monitor, fullscreen apps, Spaces, app launch/quit mid-switch,
  Accessibility denied fallback.

## Do / Don't

- **Do** update `PLAN.md` when the design changes.
- **Do** keep distribution assumptions in mind (Developer ID + notarization, not App
  Store).
- **Don't** add heavy dependencies; prefer system frameworks.
- **Don't** commit signing credentials or provisioning profiles.
