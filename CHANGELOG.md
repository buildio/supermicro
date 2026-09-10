# Changelog

## [0.2.0] - 2026-09-10
### Changed
- **Breaking:** `set_boot_override` and the `boot_to_*` helpers take `persistence:`
  instead of `enabled:`, matching the vocabulary radfish and the adapters use.
  `persistence: nil` still means `"Once"`. Callers passing `enabled:` must update.
  (#2, thanks @davispuh)

### Added
- CI on push and pull request, and a release workflow publishing to RubyGems
  through trusted publishing (OIDC), so no API key is stored in the repository.
