# Zap Privacy Policy

Effective August 16, 2026

Zap does not operate an account or analytics service, and it does not sell
personal data. It contains no advertising, telemetry, or tracking.

All settings — app exclusions, appearance and themes, per-display scoping, and
the updater's small state (enabled flag, skipped version, last-check date) —
are stored locally in Zap's application preferences on the user's Mac. Theme
export writes a `.json` file only to a location the user chooses.

Zap asks for two permissions. **Accessibility** gates the event tap that
intercepts ⌘-Tab; the keystrokes it observes are interpreted in memory to
drive the switcher and its type-to-search, and are never stored or transmitted.
Without the grant, Zap falls back to ⌥-Tab. **Screen Recording** is optional
and off by default; it is used only to draw live window preview thumbnails
inside the switcher, which are displayed and discarded — never saved or sent.

Zap's only network activity is its update check: an unauthenticated HTTPS
request to the GitHub releases API for this repository, made at launch and then
about once a day while automatic checks are enabled (they are on by default and
can be turned off in Settings), or when the user chooses to check manually. The
request identifies the app only by its bundle identifier in the User-Agent
header and includes no system-profile fields; like any network request, GitHub
receives ordinary connection metadata such as the source IP address. If the
user accepts an offered update, Zap downloads the release archive from GitHub
to `~/Downloads` and reveals it — it never installs updates itself. App icons
are read from — and icon choices made in Zap's Settings (pins, clears, and
icons migrated from older Zap versions) are written to — a local store shared
with Pict, Jetty, and Top Drawer; Zap fetches no icon artwork from the network.

Removing Zap and its application preferences removes its saved settings;
icon choices written to the shared store remain there for the other apps
that use it.
Questions can be asked through the project's GitHub repository; please report
security vulnerabilities privately, as described in [SECURITY.md](SECURITY.md).
