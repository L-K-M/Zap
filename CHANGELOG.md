# Changelog

## Unreleased

- Adopted Livery for panel theming. Theme colours now accept `#RGB` and
  `#RGBA` shorthand, reject signed strings such as `+12345`, and keep their
  alpha when a theme is exported; the CRT overlay's strength now scales
  from nothing at intensity 0 to the same look as before at full intensity,
  so settings in between look slightly fainter; the corner stripes no longer
  show a faint hairline between bands; and the decoration picker gains
  Memphis and Synthwave styles.
