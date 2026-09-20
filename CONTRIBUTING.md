# Contributing

Thanks for your interest in MagnetSimple.

## Reporting bugs

Before opening an issue, please search [existing issues](../../issues) to avoid duplicates.

Include:
- macOS version and chip (e.g., macOS 15.1, Apple M2)
- Steps to reproduce
- Any relevant logs from `Console.app` (filter by `MagnetSimple`)

## Feature requests

MagnetSimple is intentionally minimal. Proposals that keep the tool focused — high-frequency window operations, zero added complexity — are most welcome. Open an issue to discuss before writing code.

## Pull requests

1. Fork the repo
2. Create a branch: `git checkout -b feature/your-thing`
3. Commit your changes
4. Push and open a PR

### Dev setup

- macOS 13.0+
- Xcode Command Line Tools (`xcode-select --install`)
- No third-party dependencies to install

### Build & test

```bash
./build.sh
open build/MagnetSimple.app
```

### Style

- Follow standard Swift conventions
- Use `// MARK:` sections to organize files
- Keep comments concise
