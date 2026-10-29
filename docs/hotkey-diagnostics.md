# Cmd-Tab diagnostics

These diagnostics help distinguish intermittent input failures. They do not
change shortcut routing or add recovery beyond the existing timeout handler.
No typed text, other key identities, or app names are recorded. Tab key-down
messages include only a sequence number, raw modifier flags, and whether the
event matched Zap's Command-Tab trigger. Lifecycle and health messages contain
only input-system state, counters, and timing.

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
  Accessibility trust, and Secure Keyboard Entry every two seconds. It logs
  changes immediately and a summary every minute. Enabled snapshots cannot rule
  out a brief disable and recovery between checks.
- `enabled=false intendedEnabled=true` identifies a disabled hook that Zap still
  intends to use. Both false is expected while paused or using the alternate
  hotkey. No tap health is logged if a tap has never been installed.
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
   A retained tap is intentionally disabled in alternate mode.
5. Sleep and wake the Mac, then check both cycling and quick toggling. A heartbeat
   gap around sleep is expected and does not establish a fault.

The intermittent failure has not been reproduced deterministically. These checks
verify diagnostic behavior and input compatibility; they cannot establish that
the underlying issue is fixed.
