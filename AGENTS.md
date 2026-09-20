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
- **Persistence:** `UserDefaults`, plus the shared icon store via `PictKit`.
- **Dependencies:** exactly one — [`PictKit`](https://github.com/L-K-M/Pict), a
  first-party SwiftPM package holding the icon store and resolution ladder shared
  with Jetty, Top Drawer and the Pict editor. It is not what "don't add heavy
  dependencies" is about: the code in it came out of this repository.
- **Min target:** macOS 13 (Ventura) or newer.
- **App type:** Menu-bar agent (`LSUIElement = true`, no Dock icon).

## Build & Run

The Xcode project (`Zap.xcodeproj`) uses Xcode 16 file-system–synchronized groups,
so new files added under `Zap/` or `ZapTests/` are picked up automatically — no
`project.pbxproj` edits needed. **Requires Xcode 16+.**

`scripts/build.sh` builds `Zap.app` and reveals it in Finder (`scripts/build.sh
--clean` for a clean rebuild). Or invoke `xcodebuild` directly:

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
- **Don't** add heavy dependencies; prefer system frameworks. `PictKit` is the
  one exception and is first-party (see Tech Stack).
- **Don't** put icon *ingestion* back in Zap. Decoding untrusted images, running a
  `WKWebView` over fetched markup and spawning `tar` all moved to Pict precisely
  because Zap holds an Accessibility event tap and can never be sandboxed.
- **Don't** commit signing credentials or provisioning profiles.

<!-- shared-rules:start -->

## Working practices

- Follow explicit task instructions over the default workflow below.
- Before editing, inspect the branch and working tree, fetch remote updates,
  and fast-forward where safe. Never overwrite existing work to update.
- Resolve ambiguity before making consequential changes. State low-risk
  assumptions; ask when scope, safety, or expected behavior is unclear.
- Keep changes focused. Do not modify unrelated code, formatting, or comments.
- Prefer surgical edits over whole-file rewrites when the result is equivalent.
- Stage only intended files. Inspect the diff before committing.

## Communication

- Be concise, factual, and direct. Preserve necessary context and uncertainty.
- Avoid praise, motivational filler, emojis, and em dashes in new prose.
- Address the reader directly in user-facing copy.
- Report what was verified and what remains unverified. Never imply that an
  unavailable check passed.

## Code design

- Prefer early returns and shallow nesting. Separate logical blocks with
  blank lines.
- Use descriptive constants or enums for meaningful or repeated values.
  Use existing standard definitions for protocol/specification constants.
  Keep obvious, one-off values inline.
- Use enums for behavioral modes that would otherwise require ambiguous
  boolean arguments.
- Default members to private. Widen visibility only for required consumers,
  and review the change as an API design decision.
- Follow the repository's declared dependency boundaries. UI and controllers
  must use application services rather than directly accessing databases,
  subprocesses, sockets, or other low-level mechanisms.
- Encapsulate low-level mechanics behind domain-oriented interfaces.
- Reuse genuinely shared logic. Avoid speculative abstractions and layers
  that only forward calls.
- Prefer pure functions for business rules and immutable data where practical.
  Isolate side effects; document non-obvious state ownership or synchronization.
- Explain non-obvious intent, constraints, and tradeoffs in comments.
  Do not narrate obvious code. Add examples or diagrams when they clarify it.

## Validation and errors

- Validate untrusted input at entry points. Where practical, represent valid
  states in types and enforce persistent invariants in database schemas.
- Represent absence and failure explicitly.
- Use assertions for internal programming invariants, not external-input
  validation or required runtime error handling.
- Prefer explicit, actionable errors over silent failure or undocumented
  fallback. Document intentional recovery behavior.
- Never report a skipped or failed operation as successful.

## Bug fixes

1. Identify the root cause and define an observable success criterion.
2. Add a regression test and observe the relevant failure before fixing it.
3. Implement the fix and observe the test passing.
4. Check surrounding behavior for regressions and architectural consistency.

If an automated regression test is impractical, document the reproduction
and verification procedure. State any inability to reproduce the failure.

## Verification

- Run relevant tests and lint after changes.
- Choose coverage by affected behavior and risk, not patch size.
- Use integration or end-to-end tests for critical workflows and boundaries;
  test isolated business rules at the lowest effective level.
- Run broader suites for cross-cutting or high-risk changes, and the full
  required release checks before releasing.
- Validate the requested command, options, platform, and configuration.
  Unrelated green CI is not proof that the reported problem is fixed.
- Recheck after the final edit. Distinguish local checks from CI results.

## Commit messages

- Use a capitalized, imperative subject without a final period.
- Target 50 characters; never exceed 72.
- Separate the subject and body with one blank line.
- Wrap body text at 72 characters.
- Explain what changed and why. Leave implementation mechanics to the code.

## Implementation and review

Unless explicitly instructed otherwise:

1. Work on a focused branch and open a PR against main.
2. Inspect CI results and completed review feedback for the latest commit.
   A successful reviewer job does not mean the review found no problems.
3. Address important findings or explain why they do not apply. Handle minor
   findings according to the stopping rules below.
4. Evaluate each fix in the surrounding project, add regression coverage,
   and rerun affected checks before pushing.
5. Repeat until a stopping criterion is met.
6. Merge without asking again once the stopping criterion is met, required
   checks pass on the latest commit, and no unresolved blockers or required
   human review requests remain.

### Reviewer context limits

The automated PR reviewer does not see the user's original prompt or
conversation. It may suggest changes that go against or beyond what the
user asked for. Do not implement such suggestions. Note each conflict and
report it to the user at the end of the thread.

### Automated review stopping rules

Judge findings by verified impact, not the reviewer's severity label.
Important findings concern correctness, security, data loss, broken builds,
or materially degraded behavior/performance.

Track completed review rounds and consecutive rounds without important
findings. Reruns of the same revision and integration failures do not count.

- No applicable actionable feedback: finish immediately.
- First minor-only round: optionally fix worthwhile, low-risk findings.
  Do not manufacture another push merely to obtain another review.
- Two consecutive rounds without important findings: stop responding to
  automated nitpicks, even if actionable minor suggestions remain.
  Defer worthwhile leftovers rather than continuing the cycle.
- A confirmed important finding resets the minor-only streak. Address it
  and verify the fix before continuing.

After ten completed rounds, enter stabilization:

- Stop optional cleanup, refactoring, and nitpick fixes.
- One completed review without confirmed important findings is sufficient
  to finish, even if minor suggestions remain.
- Continue only for confirmed important defects. If resolving them stalls,
  report the blockers rather than continuing indefinitely.

These limits end optional automated-feedback work. They do not waive
confirmed blockers, unresolved human review requests, or required checks.

### Reviewer integration failures

After two consecutive reviewer-integration failures, stop and report the
review gap. Do not treat failures as approval. An explicit user instruction
may waive review; report that waiver rather than claiming review passed.

## Completion checklist

- The requested behavior is implemented without unrelated changes.
- Relevant checks pass for the latest code.
- Important review findings are addressed or rejected with reasons.
- Deferred suggestions, remaining risks, and validation gaps are disclosed.
- The final response accurately states whether work is committed, pushed,
  and merged.

<!-- shared-rules:end -->
