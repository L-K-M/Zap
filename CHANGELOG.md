# Changelog

## Unreleased

- Import… also reads themes exported by Jetty and Invoque, through Livery
  0.2.0's shared theme reader. Settings Zap doesn't have are skipped and Zap's
  defaults fill the rest; a glass theme whose tint the system ignores keeps
  Zap's background colour. A Zap theme with a missing or wrong-typed field now
  imports with defaults for those fields instead of failing.
- A hotkey press that arrives just as its shortcut is changed or turned off no
  longer fires the old action (Keycap 0.1.1).
- When GitHub's rate limit stops a Check for Updates, the alert says when to
  try again instead of showing a bare HTTP 403 (Updraft 0.2.0).
- Adopted Livery for panel theming. Theme colours now accept `#RGB` and
  `#RGBA` shorthand, reject signed strings such as `+12345`, and keep their
  alpha when a theme is exported; the CRT overlay's strength now scales
  from nothing at intensity 0 to the same look as before at full intensity,
  so settings in between look slightly fainter; the corner stripes no longer
  show a faint hairline between bands; and the decoration picker gains
  Memphis and Synthwave styles.
- Adopted Keycap for global hotkeys. The ⌥Tab and ⌥⇧Tab fallback keeps the
  same chords and Carbon signature; registration failures are classified by
  cause instead of collapsing to a bare failure; and “Open System Settings”
  opens the current Privacy & Security pane, falling back to the legacy
  Accessibility pane if that cannot be opened.
- Adopted Updraft for update checks. Malformed version tags and installed
  versions are now reported as unparseable instead of “you’re up to date”,
  pre-release ordering follows SemVer, and “Skip This Version” survives a
  re-tag. Downloads are verified (HTTPS GitHub hosts including redirects,
  exact size, SHA-256 when the release provides one) and carry the quarantine
  attribute so Gatekeeper checks them; assets for another OS or of an unknown
  type are no longer offered. A Check for Updates click during a background
  check is now reported instead of silently dropped. A failed download shows an
  alert offering the release page instead of opening it silently, the release
  page opened is always this repository's GitHub page, and the daily check runs
  at 90% of the interval so a punctual timer no longer skips a day.
