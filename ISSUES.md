# Zap Project Review Issues

Static review performed on 2026-06-01. Build/test verification could not be run in this environment because `xcodebuild` is not installed.

> **Resolution pass (2026-06-01):** Each item below was triaged and, where valid,
> fixed. A `**Resolution:**` note records the outcome. Code changes were made on a
> Linux host without Xcode, so they are unverified by a compiler/test run — they
> should be built and tested on macOS with Xcode 16+.

## High Priority Bugs

1. `Command+backtick` is stolen globally, not just during an active switch session.
   - References: `Zap/Hotkey/EventTapMonitor.swift:123-127`
   - The event tap handles `Command+`` before checking `isSwitching()`, starts Zap, and returns `nil`. On macOS, `Command+`` normally cycles windows within the frontmost app, so Zap will suppress a common system shortcut even when the user is not using the app switcher.
   - Fix idea: only treat `Command+`` as reverse cycling when `isSwitching()` is true, or make this behavior optional.
   - **Resolution: FIXED.** `⌘+`` is now consumed only when `isSwitching()` is already true; outside a session it passes through to the front app's native "cycle windows" behavior.

2. `Command+Tab` matching accepts unrelated modifier combinations.
   - References: `Zap/Hotkey/EventTapMonitor.swift:102-120`, `PLAN.md:81-83`
   - The handler checks only `flags.contains(.maskCommand)` and `keyCode == tab`. It will also consume combinations such as `Control+Command+Tab`, `Option+Command+Tab`, and `Function+Command+Tab`, despite the design saying only Command plus optional Shift should be intercepted.
   - Fix idea: normalize device-independent flags and require exactly Command with optional Shift.
   - **Resolution: FIXED.** A `cleanCommand` check requires Command (and optionally Shift) with **no** Control/Option/Fn held before consuming ⌘+Tab or ⌘+`. PLAN.md updated to match.

3. Initial MRU order is unreliable after launch.
   - References: `Zap/Switcher/AppListProvider.swift:50-54`, `Zap/Switcher/MRUTracker.swift:17-36`, `Zap/Switcher/SwitcherController.swift:126-129`
   - `seedMRU()` records only the current frontmost app. Every other app keeps `NSWorkspace.runningApplications` order, which is not the native app-switcher MRU order. The first `Command+Tab` after launching Zap can select the wrong previous app.
   - Fix idea: track activation history for a while before replacing the native switcher, derive a better initial order if possible, or document this limitation and avoid promising native MRU immediately after launch.
   - **Resolution: DOCUMENTED (no code change).** There is no public API for the system MRU order, so the cold-launch limitation is inherent. Documented as a "Known limitation" in `PLAN.md` (§ Most-Recently-Used ordering). Order self-corrects after the first few switches via the activation observer.

4. Excluding the current/frontmost app can make a single forward switch skip the actual previous app.
   - References: `Zap/Switcher/AppListProvider.swift:28-32`, `Zap/Switcher/SwitcherController.swift:126-129`
   - Forward switching always preselects index `1`. If the frontmost app is excluded and filtered out, index `0` may already be the previous visible app; selecting index `1` skips it.
   - Fix idea: choose the default selection based on whether the frontmost app survived filtering, not only on list count.
   - **Resolution: FIXED.** Extracted a pure `SwitcherController.defaultSelection(forward:apps:frontmostBundleID:)`: forward selection is index 1 only when the frontmost app survived filtering (it's at index 0), otherwise index 0. Covered by `SwitcherSelectionTests`.

5. Opening Settings can make Zap appear in its own switcher.
   - References: `Zap/Settings/SettingsWindowController.swift:29-36`, `Zap/ZapApp.swift:5-15`
   - The app is configured as `LSUIElement`, but the Settings window temporarily switches activation policy to `.regular`. While Settings is open, Zap can gain a Dock/app-switcher presence, violating the project constraint that Zap never appears in its own switcher.
   - Fix idea: keep the app accessory-only and use an accessory-compatible settings window presentation, or explicitly filter Zap's own bundle identifier regardless of activation policy.
   - **Resolution: FIXED.** `AppListProvider.currentApps()` now always filters out `Bundle.main.bundleIdentifier`, so Zap never lists itself even while Settings makes it `.regular`.

6. Multiple running instances with the same bundle identifier are not handled safely.
   - References: `Zap/Model/AppInfo.swift:13`, `Zap/Overlay/OverlayView.swift:25`, `Zap/Switcher/MRUTracker.swift:3-14`, `Zap/Switcher/AppListProvider.swift:35-40`
   - `AppInfo.id` and MRU tracking use only bundle identifier. Duplicate bundle IDs can produce duplicate SwiftUI `ForEach` IDs, collapse MRU entries, and cause activation to resolve to a different process via `byBundle.first`.
   - Fix idea: use process identifier in `AppInfo.id`, and track MRU by a stable per-running-app key where possible.
   - **Resolution: FIXED (partial).** `AppInfo.id` is now `"\(bundleIdentifier):\(processIdentifier)"`, making `ForEach` IDs unique; `runningApplication(for:)` already prefers a pid match. MRU intentionally stays keyed on bundle identifier (the system tracks app-level, not process-level, recency), which is the correct granularity for switcher ordering.

7. Window close failures are ignored and desynchronize the overlay.
   - References: `Zap/Switcher/SwitcherController.swift:316-324`, `Zap/Switcher/WindowEnumerator.swift:65-77`
   - `closeFocusedWindow()` removes the selected window from Zap's list whether or not `WindowEnumerator.close()` succeeds. A window with no close button, a denied AX action, or a failed press will stay open while disappearing from the overlay.
   - Fix idea: remove the row only when close succeeds, or re-enumerate windows after attempting close.
   - **Resolution: FIXED.** `closeFocusedWindow()` now returns early unless `WindowEnumerator.close()` reports success, so a window that can't be closed stays in the list.

8. Forced Accessibility casts can crash during window close.
   - References: `Zap/Switcher/WindowEnumerator.swift:69-77`, `Zap/Switcher/WindowEnumerator.swift:89-97`
   - `button as! AXUIElement` and `value as! CFBoolean` assume AX returns the expected CF types. AX APIs can return unexpected values for unusual apps or windows, causing Zap to crash in switcher UI code.
   - Fix idea: replace forced casts with type checks and return failure when the AX value is not the expected type.
   - **Resolution: FIXED.** The close-button cast is now guarded by `CFGetTypeID(button) == AXUIElementGetTypeID()`, returning failure otherwise. The `CFBoolean` cast was already guarded by a `CFBooleanGetTypeID()` check (now confirmed safe).

## Medium Priority Bugs And UX Gaps

1. The alternate-hotkey preference is persisted but not honored.
   - References: `Zap/Model/Preferences.swift:105-107`, `Zap/Settings/GeneralView.swift:35-37`, `Zap/Switcher/SwitcherController.swift`
   - Changing the toggle at runtime does not reconfigure hotkeys.
   - **Resolution: FIXED.** `useAlternateHotkey` now means "force the ⌥-Tab fallback". `SwitcherController.applyInputMode()` is the single place that (re)configures the trigger and is invoked on start, resume, and — via a Combine subscription — whenever the preference changes.

2. Carbon fallback registration failures are silently ignored.
   - References: `Zap/Switcher/SwitcherController.swift:101-102`, `Zap/Hotkey/CarbonHotkey.swift:68-76`
   - **Resolution: FIXED.** `startFallback()` now returns whether registration succeeded; the result drives an `InputModeReporter` (`.fallback` vs `.unavailable`) surfaced in the Permissions tab, and failures are logged.

3. Failed Carbon registration can leave an installed event handler.
   - References: `Zap/Hotkey/CarbonHotkey.swift:57-76`
   - **Resolution: FIXED.** `register(...)` calls `unregister()` (which removes the event handler) before returning `false` on a failed `RegisterEventHotKey`.

4. Launch-at-login preference can lie after `SMAppService` errors.
   - References: `Zap/Model/Preferences.swift:98-103`, `Zap/Model/Preferences.swift:149-163`
   - **Resolution: FIXED.** `applyLaunchAtLogin` persists only on success, rolls the toggle back to the real `SMAppService` status on failure (guarded against `didSet` re-entrancy), and publishes `launchAtLoginError`, which `GeneralView` displays.

5. Launch-at-login UI does not reflect external system changes.
   - References: `Zap/Model/Preferences.swift:129`, `Zap/Settings/GeneralView.swift:10`
   - **Resolution: FIXED.** The toggle is seeded from `SMAppService.mainApp.status` at init, and `refreshLaunchAtLoginStatus()` is called from `GeneralView.onAppear` to re-sync when Settings opens.

6. Overlay can extend off-screen with many apps or large icons.
   - References: `Zap/Overlay/OverlayView.swift:24-55`, `Zap/Overlay/OverlayWindowController.swift:157-158`
   - **Resolution: FIXED.** The icon row is capped to `model.maxContentWidth` (derived from the target screen, set in `layout`) and scrolls horizontally beyond that; the window frame is clamped to the screen's `visibleFrame` in both axes.

7. Window enumeration may show non-standard or transient windows when subrole lookup fails.
   - References: `Zap/Switcher/WindowEnumerator.swift:37-47`
   - **Resolution: FIXED.** Enumeration now *requires* `kAXStandardWindowSubrole`; a missing/unreadable subrole means the window is skipped rather than included.

8. App/window activation failures are ignored.
   - References: `Zap/Switcher/SwitcherController.swift:337-343`, `Zap/Switcher/WindowEnumerator.swift:55-60`
   - **Resolution: FIXED.** Return values of `activate`, `AXUIElementSetAttributeValue`/`PerformAction` are checked and logged via `NSLog` for diagnostics.

9. The app list can become stale during a switch session.
   - References: `Zap/Switcher/SwitcherController.swift:123-129`, `Zap/Switcher/SwitcherController.swift:165-176`
   - **Resolution: ACKNOWLEDGED (not changed).** Snapshotting at session start keeps the hot path allocation-light, and commit safely no-ops when the selected app's process is gone (`runningApplication(for:)` resolves nothing to activate). Quit handling already refreshes the list. Live workspace-notification refresh during a visible session is deferred as a future enhancement to avoid mid-switch list churn.

10. Exclusions UI only lists currently running apps.
    - References: `Zap/Settings/ExclusionsView.swift:51-55`
    - **Resolution: FIXED.** `reload()` now also includes excluded bundle IDs that aren't running, resolving a display name and icon from the installed app bundle (falling back to the bundle ID), so they can be reviewed and re-enabled.

11. Preferences values are not validated on load.
    - References: `Zap/Model/Preferences.swift:117-128`
    - **Resolution: FIXED.** Numeric values are clamped to sane ranges (with NaN/inf fallback to defaults) and color strings fall back to defaults when they don't parse. Covered by new `PreferencesTests`.

12. Permissions status can claim `Command+Tab` interception is active even if the tap failed.
    - References: `Zap/Settings/PermissionsView.swift:18`
    - **Resolution: FIXED.** `PermissionsView` now reads the live `InputModeReporter` (`eventTap` / `fallback` / `unavailable` / `paused`) instead of inferring mode from the permission grant alone.

13. Pause/resume may not recover if Accessibility is granted while the app is running.
    - References: `Zap/Switcher/SwitcherController.swift:57-80`
    - **Resolution: FIXED.** `resume()` calls `applyInputMode()`, which re-evaluates permission state and promotes fallback → event tap once Accessibility is granted (no relaunch needed).

## Tests And Verification Gaps

1. Build and tests were not verified in this review environment.
   - **Resolution: STILL OPEN (environmental).** `xcodebuild` is unavailable on this Linux host; run `xcodebuild -project Zap.xcodeproj -scheme Zap -destination 'platform=macOS' test` on macOS with Xcode 16+.

2. There are no tests for switcher selection behavior.
   - **Resolution: FIXED (partial).** Default-selection logic was extracted to a pure static function and is covered by `ZapTests/SwitcherSelectionTests.swift` (forward/reverse, excluded-frontmost, single/empty). Reverse-cycling/commit/cancel still rely on AppKit and remain untested.

3. There are no tests for launch-at-login behavior or errors.
   - **Resolution: DEFERRED.** Properly testing this needs an injectable launch-at-login service abstraction (improvement idea) to avoid touching the real `SMAppService`; not added in this pass.

4. There are no tests for fallback-hotkey preference behavior.
   - **Resolution: PARTIALLY ADDRESSED.** The preference now drives `applyInputMode()`; a full test still needs the input-mode logic decoupled from Carbon/event-tap globals.

5. There are no tests for bad persisted preference values.
   - **Resolution: FIXED.** Added tests for invalid color strings, out-of-range opacity/icon size/delays, and non-finite values in `PreferencesTests`.

6. Unit tests host the real app binary and rely on runtime guards to avoid installing global hooks.
   - **Resolution: ACKNOWLEDGED.** The `isRunningTests` guard remains; a separate pure-logic bundle is left as a future improvement.

## Documentation Mismatches

1. `PLAN.md` says the event tap listens for `keyUp`, but the implementation does not.
   - **Resolution: FIXED.** PLAN now lists `keyDown` + `flagsChanged`.

2. `PLAN.md` documents `.` cancel and `H` hide, but code does not implement them.
   - **Resolution: FIXED.** The key table now reflects the real keys (Esc, Q, W, ↑/↓, Tab, backtick, hover/click).

3. README says the fallback is graceful, but registration failures are silent.
   - **Resolution: FIXED.** Failures are now surfaced (Permissions tab / logs); README reworded to mention the active-trigger reporting.

4. README states Zap never appears in its own switcher, but Settings can make it regular.
   - **Resolution: FIXED.** Now enforced by filtering Zap's own bundle ID (see High #5); README claim is accurate.

5. `PLAN.md` project structure lists files that differ from the current project.
   - **Resolution: FIXED.** The structure tree was updated to match the actual files (e.g. `OverlayWindowController.swift`, `InputModeReporter.swift`, generated Info.plist).

6. README signing guidance is manual but project config has no development team set.
   - **Resolution: ACKNOWLEDGED.** Intentional for an open-source repo; contributors configure their own signing.

## Repository Hygiene

1. User/tool-specific metadata is tracked.
   - References: `.idea/*`, `.codenomad/worktreeMap.json`
   - **Resolution: FIXED (gitignore).** `.idea/`, `.codenomad/`, and `.vscode/` added to `.gitignore`. Existing tracked copies should be removed with `git rm -r --cached` in a real git checkout (this environment is not a git repo).

2. `.DS_Store` files exist in the working tree.
   - **Resolution: FIXED.** Removed `.DS_Store` and `Zap/.DS_Store` from the working tree (already ignored).

3. No shared Xcode scheme is visible in the repository.
   - **Resolution: INVALID.** A shared scheme exists at `Zap.xcodeproj/xcshareddata/xcschemes/Zap.xcscheme`. The review listing missed it.

## Improvement Ideas

1. Add an explicit onboarding/permission state machine.
   - **Status: PARTIALLY DONE.** `SwitcherInputMode`/`InputModeReporter` model the live trigger state shared with Settings; a fuller onboarding flow remains future work.

2. Split pure switcher-session logic out of `SwitcherController`.
   - **Status: STARTED.** `defaultSelection(...)` is now a pure, tested function; more of the session logic could follow.

3. Persist previously seen apps for exclusions.
   - **Status: PARTIALLY DONE.** Excluded non-running apps are now resolvable from disk; persisting a name/icon cache for uninstalled apps remains future work.

4. Add a debug diagnostics panel or log messages for hotkey/tap failures.
   - **Status: PARTIALLY DONE.** Failures now log via `NSLog`; a visible diagnostics panel remains future work.

5. Clamp overlay size to the active display and support scrolling for large app sets.
   - **Status: DONE.** See Medium #6.

6. Consider keeping Settings accessory-style instead of switching the whole app to `.regular`.
   - **Status: MITIGATED.** The self-listing invariant is now enforced by bundle-ID filtering regardless of activation policy; converting Settings to a fully accessory-style presentation remains optional future work.
