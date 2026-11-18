# Changelog

## Unreleased

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
