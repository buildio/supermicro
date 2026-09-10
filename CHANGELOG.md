# Changelog

## [0.2.1] - 2026-09-11
### Security
- Requires httparty >= 0.24.0. The old `~> 0.21` constraint permitted versions
  up to 0.23.2, which carry an SSRF issue that can leak API keys (high).
  httparty is used for the `HTTParty.get` call in `Supermicro::Client`, so this
  reached anyone installing the gem, unlike a lockfile pin. idrac already
  required 0.24.

## [0.2.0] - 2026-09-10
### Changed
- **Breaking:** `set_boot_override` and the `boot_to_*` helpers take `persistence:`
  instead of `enabled:`, matching the vocabulary radfish and the adapters use.
  `persistence: nil` still means `"Once"`. Callers passing `enabled:` must update.
  (#2, thanks @davispuh)

### Added
- CI on push and pull request, and a release workflow publishing to RubyGems
  through trusted publishing (OIDC), so no API key is stored in the repository.
