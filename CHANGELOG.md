# Changelog

Format based on [Keep a Changelog](https://keepachangelog.com/). This project follows [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-09-20

Initial release.

### Added
- Left/right snap with ½ → ⅓ → ⅔ cycle on repeated presses
- Maximize/restore toggle with per-window position memory
- Multi-display support (auto-detects screen, accounts for menu bar and Dock)
- Menu bar resident with horseshoe magnet vector icon (no Dock presence)
- Launch at login via native `SMAppService` API
- Runtime Accessibility permission detection — no app restart needed after granting
- Dual modifier key support: `Control+Option` and `Control`-only for keyboards without Option
- Universal Binary: arm64 + x86_64
- Tolerance-based snap detection for apps with minimum window size constraints
