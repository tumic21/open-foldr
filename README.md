# OpenFoldr

Cross-platform local network directory sync and collaboration.

OpenFoldr aims to provide a fast and secure way to share local folders over a LAN with controlled permissions, conflict-aware editing, and strong filesystem safety.

## Vision

- Share one or more folders with root aliases.
- Discover hosts on LAN using mDNS, with manual fallback.
- Browse, upload, edit, and delete files with role-based access.
- Keep traffic encrypted and enforce sandboxed filesystem access.

## Planned Stack

- Flutter (Linux, Windows, Android, iOS)
- Dart backend (HTTP and WebSocket)
- mDNS discovery
- TLS-secured transport

## Getting Started

This repository currently contains product and engineering planning documents.

Implementation bootstrap will be added in upcoming milestones.

## Project Roadmap

See _project/spec/spec.md and _project/spec/implementation-board.md.

## Branching Strategy

- `develop` is the active integration branch for day-to-day work.
- `main` is the stable branch for releases and tagged milestones.
- Feature branches should be created from `develop` and merged back into `develop` via pull request.
- Release pull requests should merge `develop` into `main`.

## Security

Please review SECURITY.md before reporting vulnerabilities.

## License

Licensed under Apache License 2.0.
