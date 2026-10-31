# Cmd-Tab diagnostics

Zap validates its keyboard subscription and retries failed input setup. These
diagnostics distinguish incomplete registrations from other input failures.
No typed text, other key identities, or app names are recorded.
Tab key-down messages include only a sequence number, raw modifier flags, and
whether the event matched Zap's Command-Tab trigger. Lifecycle and health
messages contain only input-system state, counters, and timing.

## Registration validity check

After each `CGEventTapCreate`, Zap inspects the returned tap's
`CGEventTapIsEnabled` state and the actual event-mask subscription. A valid
registration must include `keyDown`, `keyUp`, and `flagsChanged` (combined
mask 7168). CoreGraphics may silently drop keyboard bits, returning a tap
that reports enabled yet carries only `flagsChanged` (mask 4096). Such
incomplete or otherwise unverifiable registrations are disposed immediately.

A tap that is valid, enabled, and carries Accessibility trust does not by
itself guarantee a complete keyboard subscription. The `registeredEvents`
health log field reports the actual integer mask (or `unknown` when the
query fails) so that partial registrations are visible without assuming
correctness from validity or enabled state alone.

## Retry behavior

When a registration fails the validity check, `SwitcherController` retries
eligible input setup every 2 seconds. The retry loop respects pause state
and any forced alternate hotkey selection. The Carbon fallback hotkey
remains active until a verified event-tap registration succeeds. When
Accessibility permission is granted after a denial, the controller
re-evaluates input setup automatically. Promotion from fallback waits for an
active fallback selection to finish. Existing timeout re-enable and
input routing logic remain unchanged.

## Captured failure case (2026-10-31)

A logged incident showed Accessibility granted, a tap that reported valid
and enabled, yet the event mask carried only 4096 (`flagsChanged` without
keyboard bits). Zero Tab receipts arrived. Relaunching the same binary
immediately produced a correct registration with mask 7168. TCC logged a failure
to obtain Zap's code reference and refused `ListenEvent` access during startup.
The startup timing is not deterministically reproducible, and the
cause should not be assumed for every historical incident.

## Capture an incident

Use a build that includes `EventTapDiagnostics`. To watch its messages:

```sh
log stream --style compact --level info --predicate 'subsystem == "ch.lkmc.Zap" AND category == "HotkeyDiagnostics"'
```

If the native switcher appears, leave Zap running. Note the approximate time,
whether you held extra modifiers, and whether a subsequent attempt recovers.
Retrieve the recent history with:

```sh
log show --last 10m --style compact --info --predicate 'subsystem == "ch.lkmc.Zap" AND category == "HotkeyDiagnostics"'
```

Only share this filtered output. Other system logs can contain unrelated data.

## Interpret the evidence

- `Tab #... received` confirms the event reached Zap. `matchedTrigger=true`
  means Command was held without Control, Option, or Fn. This is recorded before
  controller work, so a stalled callback can still leave a receipt.
- `matchedTrigger=false` means the event did not match the opening shortcut.
  The modifier flags can explain why. During an existing switch session Zap can
  still consume that Tab, so this field does not describe every routing decision.
- No matching Tab receipt suggests an input-delivery issue, but does not prove
  another app intercepted it. Logs are asynchronous and system retention varies.
- A `slow callback` records Tab handling that took at least 100 ms. A
  `Tap disabled by timeout` message reports macOS's actual timeout notification.
  A slow callback alone does not prove a timeout. Its duration excludes time
  waiting for delivery before the handler began.
- `Tap health` checks validity, actual enabled state, intended enabled state,
  Accessibility trust, Secure Keyboard Entry, and `registeredEvents` every two
  seconds. The `registeredEvents` field reports the actual integer event mask
  (or `unknown` when the query fails). It logs changes immediately and a summary
  every minute. Enabled snapshots cannot rule out a brief disable and recovery
  between checks.
- `enabled=false intendedEnabled=true` identifies a disabled hook that Zap still
  intends to use. Both false is expected while paused. Alternate mode removes
  the tap. Rejected registrations have lifecycle messages instead of periodic
  tap health, because the rejected connection is disposed immediately.
- `heartbeatGapMs` over 5000 records a delayed main-loop check. Sleep, scheduling,
  and blocking work can all cause this; it is not proof of a hang. Correlate it
  with the incident time, shortcut receipts, and system-condition transitions.

## Manual verification

1. Hold Command and press Tab, then Shift-Tab. Confirm Zap cycles in both
   directions and releasing Command commits. A quick Command-Tab should preserve
   the normal two-app toggle. Check for receipts with `matchedTrigger=true`.
2. Outside a switch session, try Control-Command-Tab, Option-Command-Tab, and
   Fn-Command-Tab. Confirm Zap leaves them alone and reports false trigger matches.
3. Pause and resume Zap. Confirm the native switcher works while paused and Zap
   handles Command-Tab after resuming. Check intended and actual enabled state.
4. Select the alternate hotkey, confirm it works, then restore the normal mode.
   The event tap is removed in alternate mode. Confirm pause
   state and alternate hotkey selection are not overridden by the retry loop.
5. Sleep and wake the Mac, then check both cycling and quick toggling. A heartbeat
   gap around sleep is expected and does not establish a fault.
6. Deny Accessibility, then grant it while Zap is running. Confirm Zap
   re-evaluates input setup and registers a complete event tap (mask 7168)
   without requiring a relaunch.
7. After login or wake, verify `registeredEvents` reports 7168. A rejected partial
   mask (4096) should be followed by another setup attempt; recovery requires
   macOS to allow keyboard access. Confirm the verified tap remains stable.

Automated lifecycle tests inject incomplete, unknown, invalid, and complete
connections. A separate manual probe exercises real registration lookup and
disposal without keyboard access. These checks verify rejection and retry
behavior; they do not reproduce macOS's login-time permission-service failure.
