# Security Policy

## Supported versions

Security fixes are provided for the latest released version of Zap.

## Reporting a vulnerability

Please use GitHub's private vulnerability reporting feature for this repository.
Do not include private keys, passwords, or other secrets in a report. If private
reporting is unavailable, open an issue that contains no sensitive details and
request a private contact channel.

## Security boundary

Zap's security boundary is intentionally narrow. The Accessibility permission
gates a `CGEventTap` that intercepts the switcher keys (⌘-Tab and friends);
keyboard events are interpreted in memory to drive the switcher and its
type-to-search, and are never persisted or transmitted. The optional Screen
Recording permission (off by default) is used only to render live window
thumbnails inside the switcher; captures are displayed and discarded, never
written to disk or sent anywhere. The app's only network endpoint is the GitHub
releases API over HTTPS, used to check for updates; the updater never installs
anything itself — at most it saves the release archive to `~/Downloads` for the
user to open. App icons come from a local store shared with Pict, Jetty, and
Top Drawer; decoding untrusted icon images from the network is deliberately
Pict's job, not Zap's. Release builds are ad-hoc signed and not notarized, so
Gatekeeper warns on first launch — download Zap only from this repository's
Releases page.
