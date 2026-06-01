# Zap Project Review Issues

Static review performed on 2026-06-01. Build/test verification could not be run in this environment because `xcodebuild` is not installed.

## High Priority Bugs

1. `Command+backtick` is stolen globally, not just during an active switch session.
   - References: `Zap/Hotkey/EventTapMonitor.swift:123-127`
   - The event tap handles `Command+`` before checking `isSwitching()`, starts Zap, and returns `nil`. On macOS, `Command+`` normally cycles windows within the frontmost app, so Zap will suppress a common system shortcut even when the user is not using the app switcher.
   - Fix idea: only treat `Command+`` as reverse cycling when `isSwitching()` is true, or make this behavior optional.

2. `Command+Tab` matching accepts unrelated modifier combinations.
   - References: `Zap/Hotkey/EventTapMonitor.swift:102-120`, `PLAN.md:81-83`
   - The handler checks only `flags.contains(.maskCommand)` and `keyCode == tab`. It will also consume combinations such as `Control+Command+Tab`, `Option+Command+Tab`, and `Function+Command+Tab`, despite the design saying only Command plus optional Shift should be intercepted.
   - Fix idea: normalize device-independent flags and require exactly Command with optional Shift.

3. Initial MRU order is unreliable after launch.
   - References: `Zap/Switcher/AppListProvider.swift:50-54`, `Zap/Switcher/MRUTracker.swift:17-36`, `Zap/Switcher/SwitcherController.swift:126-129`
   - `seedMRU()` records only the current frontmost app. Every other app keeps `NSWorkspace.runningApplications` order, which is not the native app-switcher MRU order. The first `Command+Tab` after launching Zap can select the wrong previous app.
   - Fix idea: track activation history for a while before replacing the native switcher, derive a better initial order if possible, or document this limitation and avoid promising native MRU immediately after launch.

4. Excluding the current/frontmost app can make a single forward switch skip the actual previous app.
   - References: `Zap/Switcher/AppListProvider.swift:28-32`, `Zap/Switcher/SwitcherController.swift:126-129`
   - Forward switching always preselects index `1`. If the frontmost app is excluded and filtered out, index `0` may already be the previous visible app; selecting index `1` skips it.
   - Fix idea: choose the default selection based on whether the frontmost app survived filtering, not only on list count.

5. Opening Settings can make Zap appear in its own switcher.
   - References: `Zap/Settings/SettingsWindowController.swift:29-36`, `Zap/ZapApp.swift:5-15`, `Zap.xcodeproj/project.pbxproj:317`
   - The app is configured as `LSUIElement`, but the Settings window temporarily switches activation policy to `.regular`. While Settings is open, Zap can gain a Dock/app-switcher presence, violating the project constraint that Zap never appears in its own switcher.
   - Fix idea: keep the app accessory-only and use an accessory-compatible settings window presentation, or explicitly filter Zap's own bundle identifier regardless of activation policy.

6. Multiple running instances with the same bundle identifier are not handled safely.
   - References: `Zap/Model/AppInfo.swift:13`, `Zap/Overlay/OverlayView.swift:25`, `Zap/Switcher/MRUTracker.swift:3-14`, `Zap/Switcher/AppListProvider.swift:35-40`
   - `AppInfo.id` and MRU tracking use only bundle identifier. Duplicate bundle IDs can produce duplicate SwiftUI `ForEach` IDs, collapse MRU entries, and cause activation to resolve to a different process via `byBundle.first`.
   - Fix idea: use process identifier in `AppInfo.id`, and track MRU by a stable per-running-app key where possible.

7. Window close failures are ignored and desynchronize the overlay.
   - References: `Zap/Switcher/SwitcherController.swift:316-324`, `Zap/Switcher/WindowEnumerator.swift:65-77`
   - `closeFocusedWindow()` removes the selected window from Zap's list whether or not `WindowEnumerator.close()` succeeds. A window with no close button, a denied AX action, or a failed press will stay open while disappearing from the overlay.
   - Fix idea: remove the row only when close succeeds, or re-enumerate windows after attempting close.

8. Forced Accessibility casts can crash during window close.
   - References: `Zap/Switcher/WindowEnumerator.swift:69-77`, `Zap/Switcher/WindowEnumerator.swift:89-97`
   - `button as! AXUIElement` and `value as! CFBoolean` assume AX returns the expected CF types. AX APIs can return unexpected values for unusual apps or windows, causing Zap to crash in switcher UI code.
   - Fix idea: replace forced casts with type checks and return failure when the AX value is not the expected type.

## Medium Priority Bugs And UX Gaps

1. The alternate-hotkey preference is persisted but not honored.
   - References: `Zap/Model/Preferences.swift:105-107`, `Zap/Settings/GeneralView.swift:35-37`, `Zap/Switcher/SwitcherController.swift:57-63`, `Zap/Switcher/SwitcherController.swift:95-103`
   - The setting says users can use the `Option+Tab` fallback, but `SwitcherController` always uses the event tap when trusted and always starts fallback when not trusted. Changing the toggle at runtime does not reconfigure hotkeys.
   - Fix idea: decide whether this setting means "force alternate hotkey" or "enable fallback", then wire it into startup/resume and observe preference changes.

2. Carbon fallback registration failures are silently ignored.
   - References: `Zap/Switcher/SwitcherController.swift:101-102`, `Zap/Hotkey/CarbonHotkey.swift:68-76`
   - `register(...)` returns `Bool`, but the caller ignores the result. If `Option+Tab` is unavailable or registration fails, users get no fallback despite the UI and README promising one.
   - Fix idea: surface registration failure in the Permissions/General UI and avoid claiming fallback is active unless both hotkeys registered.

3. Failed Carbon registration can leave an installed event handler.
   - References: `Zap/Hotkey/CarbonHotkey.swift:57-76`
   - `InstallEventHandler` runs before `RegisterEventHotKey`. If registration fails, the method returns `false` without removing the event handler.
   - Fix idea: call `unregister()` or `RemoveEventHandler(eventHandler)` before returning failure.

4. Launch-at-login preference can lie after `SMAppService` errors.
   - References: `Zap/Model/Preferences.swift:98-103`, `Zap/Model/Preferences.swift:149-163`
   - The value is saved to `UserDefaults` before `SMAppService.mainApp.register()` or `unregister()` completes. If the OS operation throws, the toggle remains set even though login-item state did not change.
   - Fix idea: model launch-at-login state from `SMAppService.mainApp.status`, roll back on failure, and expose an error to Settings.

5. Launch-at-login UI does not reflect external system changes.
   - References: `Zap/Model/Preferences.swift:129`, `Zap/Settings/GeneralView.swift:10`
   - The toggle initializes from `UserDefaults`, not the current `SMAppService.mainApp.status`. If the user changes login items in System Settings, the UI can become stale.
   - Fix idea: query `SMAppService.mainApp.status` when displaying Settings and after toggling.

6. Overlay can extend off-screen with many apps or large icons.
   - References: `Zap/Overlay/OverlayView.swift:24-55`, `Zap/Overlay/OverlayWindowController.swift:157-158`, `PLAN.md:152`
   - The app row is a fixed-size `HStack`, `.fixedSize()` is applied, and the centered window is not clamped to the screen. Many running apps can create a panel wider than the display.
   - Fix idea: cap width to the target screen and use horizontal scrolling or wrapping.

7. Window enumeration may show non-standard or transient windows when subrole lookup fails.
   - References: `Zap/Switcher/WindowEnumerator.swift:37-47`
   - The filter excludes non-standard windows only when a subrole is present and not `kAXStandardWindowSubrole`. If the subrole attribute is missing or inaccessible, the window is included.
   - Fix idea: require `kAXStandardWindowSubrole` unless there is a known app-specific exception.

8. App/window activation failures are ignored.
   - References: `Zap/Switcher/SwitcherController.swift:337-343`, `Zap/Switcher/WindowEnumerator.swift:55-60`
   - `activate`, `AXUIElementSetAttributeValue`, and `AXUIElementPerformAction` can fail, but no return values are checked. Failed switches will be silent and hard to diagnose.
   - Fix idea: check return values at least for logging and future UI diagnostics.

9. The app list can become stale during a switch session.
   - References: `Zap/Switcher/SwitcherController.swift:123-129`, `Zap/Switcher/SwitcherController.swift:165-176`
   - Zap snapshots apps at session start and does not revalidate the list until commit, except for quit handling. If the selected app quits or a new app launches mid-session, the overlay may show dead entries or omit new ones.
   - Fix idea: revalidate selected app before commit and consider refreshing on workspace launch/terminate notifications while the overlay is visible.

10. Exclusions UI only lists currently running apps.
    - References: `Zap/Settings/ExclusionsView.swift:51-55`, `PLAN.md:137`
    - The plan says Settings should list currently running plus previously seen apps. Today an excluded app that is not running cannot be reviewed or re-enabled from Settings.
    - Fix idea: persist seen apps with name/icon metadata or show excluded bundle IDs even when the app is not running.

11. Preferences values are not validated on load.
    - References: `Zap/Model/Preferences.swift:117-128`, `Zap/Overlay/OverlayView.swift:53-61`, `Zap/Switcher/SwitcherController.swift:131`, `Zap/Switcher/SwitcherController.swift:260`
    - Sliders constrain new UI input, but corrupted or manually edited defaults can load negative opacity, huge icon sizes, invalid delays, or invalid colors. Invalid colors currently fall back to `.clear`, which can make UI invisible.
    - Fix idea: clamp numeric values and fall back to default colors during initialization.

12. Permissions status can claim `Command+Tab` interception is active even if the tap failed.
    - References: `Zap/Settings/PermissionsView.swift:18`, `Zap/AppDelegate.swift:77-80`, `Zap/Switcher/SwitcherController.swift:57-63`
    - `PermissionsView` displays based only on `AccessibilityAuthorizer.isTrusted`. `eventTap.start()` can still fail after trust is granted, causing the app to use fallback while Settings says interception is active.
    - Fix idea: expose actual input mode from `SwitcherController` to the permissions UI.

13. Pause/resume may not recover if Accessibility is granted while the app is running.
    - References: `Zap/Switcher/SwitcherController.swift:57-80`, `Zap/AppDelegate.swift:77-80`
    - `usesEventTap` is chosen at startup. If the app starts in fallback mode, then the user grants Accessibility, `resume()` still restarts fallback because `usesEventTap` remains false. The README says to relaunch, but the UI polls permission status and can imply live activation.
    - Fix idea: on resume or permission change, retry `eventTap.start()` when `AccessibilityAuthorizer.isTrusted` becomes true.

## Tests And Verification Gaps

1. Build and tests were not verified in this review environment.
   - Command attempted: `xcodebuild -version`
   - Result: `xcodebuild: command not found`
   - Follow-up: run `xcodebuild -project Zap.xcodeproj -scheme Zap -destination 'platform=macOS' test` on a macOS machine with Xcode 16+.

2. There are no tests for switcher selection behavior.
   - References: `Zap/Switcher/SwitcherController.swift:122-153`, `ZapTests/MRUTrackerTests.swift`
   - Current tests cover MRU sorting but not default selection, excluded-frontmost behavior, reverse cycling, cancel/commit behavior, or app-list refresh decisions.
   - Fix idea: extract pure session-selection logic so it can be unit tested without AppKit event taps.

3. There are no tests for launch-at-login behavior or errors.
   - References: `Zap/Model/Preferences.swift:98-103`, `Zap/Model/Preferences.swift:149-163`, `ZapTests/PreferencesTests.swift`
   - `Preferences(defaults:)` injects storage but not the `SMAppService` side effect, making safe unit tests difficult.
   - Fix idea: inject a small launch-at-login service abstraction.

4. There are no tests for fallback-hotkey preference behavior.
   - References: `Zap/Model/Preferences.swift:105-107`, `Zap/Switcher/SwitcherController.swift:95-103`
   - The current ineffective setting would likely have been caught by a test asserting startup mode from preferences.

5. There are no tests for bad persisted preference values.
   - References: `Zap/Model/Preferences.swift:117-128`, `ZapTests/PreferencesTests.swift:23-67`
   - Tests cover happy-path defaults and round trips only.
   - Fix idea: add tests for invalid color strings, out-of-range opacity/icon sizes, and delay values after adding validation.

6. Unit tests host the real app binary and rely on runtime guards to avoid installing global hooks.
   - References: `Zap.xcodeproj/project.pbxproj:354-363`, `Zap/AppDelegate.swift:16-18`, `Zap/AppDelegate.swift:83-86`
   - The guard is sensible, but a separate pure-logic test bundle or additional dependency injection would reduce the risk of event taps/status items being touched during tests.

## Documentation Mismatches

1. `PLAN.md` says the event tap listens for `keyUp`, but the implementation does not.
   - References: `PLAN.md:78-80`, `Zap/Hotkey/EventTapMonitor.swift:45-48`
   - This may be intentional because command release is handled through `flagsChanged`, but the plan is stale.

2. `PLAN.md` documents `.` cancel and `H` hide, but code does not implement them.
   - References: `PLAN.md:101-104`, `Zap/Hotkey/EventTapMonitor.swift:133-155`
   - Code handles Escape, Q, W, arrows, Tab, and backtick.

3. README says the fallback is graceful, but registration failures are silent.
   - References: `README.md:18`, `Zap/Switcher/SwitcherController.swift:101-102`
   - The product can end up with no fallback if Carbon registration fails.

4. README states Zap never appears in its own switcher, but Settings can make it regular.
   - References: `README.md:16`, `Zap/Settings/SettingsWindowController.swift:29-36`

5. `PLAN.md` project structure lists files that differ from the current project.
   - References: `PLAN.md:224-246`
   - Example: it lists `OverlayWindow.swift`, while the project has `OverlayWindowController.swift`; Info.plist is generated rather than checked in.

6. README signing guidance is manual but project config has no development team set.
   - References: `README.md:63-70`, `Zap.xcodeproj/project.pbxproj:310-344`
   - This is reasonable for an open-source repo, but contributors should expect repeated Accessibility prompts until they configure signing.

## Repository Hygiene

1. User/tool-specific metadata is tracked.
   - References: `.idea/Zap.iml`, `.idea/misc.xml`, `.idea/modules.xml`, `.idea/swift-toolchain.xml`, `.idea/vcs.xml`, `.codenomad/worktreeMap.json`
   - These files are likely local to one developer/tool setup and can create noisy diffs. `.codenomad/worktreeMap.json` was modified in the current worktree during review.

2. `.DS_Store` files exist in the working tree.
   - References: `.DS_Store`, `Zap/.DS_Store`
   - They are ignored by `.gitignore`, but still present locally.

3. No shared Xcode scheme is visible in the repository.
   - References: `Zap.xcodeproj/project.xcworkspace/xcshareddata` absent in the file listing
   - `xcodebuild -scheme Zap` may still work through automatic scheme generation, but a shared scheme is more reliable for CI and contributors.

## Improvement Ideas

1. Add an explicit onboarding/permission state machine.
   - Track actual modes: event tap active, fallback active, paused, permission missing, registration failed. Use the same state in Settings and menu-bar UI.

2. Split pure switcher-session logic out of `SwitcherController`.
   - This would make selection, filtering, default index, window-list navigation, and quit/remove behavior testable without AppKit globals.

3. Persist previously seen apps for exclusions.
   - Store bundle identifier and display name so users can manage exclusions when apps are not running.

4. Add a debug diagnostics panel or log messages for hotkey/tap failures.
   - Event taps, AX actions, Carbon hotkeys, and launch-at-login all fail for environmental reasons; visible diagnostics would reduce support friction.

5. Clamp overlay size to the active display and support scrolling for large app sets.
   - This is needed before the app feels robust for users with many running apps.

6. Consider keeping Settings accessory-style instead of switching the whole app to `.regular`.
   - This protects the core invariant that Zap never appears as a switchable app.
