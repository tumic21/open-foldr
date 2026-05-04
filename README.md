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

### Prerequisites

- [Flutter SDK](https://flutter.dev/docs/get-started/install) (stable channel)
- Dart (bundled with Flutter)
- For Android: Android SDK with emulator or physical device
- For Linux: CMake, Ninja, `clang`, `pkg-config` (see `flutter doctor`)
- For Windows: Visual Studio 2022 with C++ workload

Install dependencies:

```bash
flutter pub get
```

---

### Run on Linux (desktop)

```bash
flutter run -d linux
```

---

### Run on Windows (desktop)

```bash
flutter run -d windows
```

---

### Run on Android emulator

1. Start the emulator (one-time AVD creation):

```bash
# List available AVDs
~/Android/Sdk/emulator/emulator -list-avds

# Launch an AVD
~/Android/Sdk/emulator/emulator -avd <avd-name> -no-snapshot-save
```

2. Run the app:

```bash
flutter run -d emulator-5554
```

For verbose build output:

```bash
flutter run -v -d emulator-5554
```

---

### Run on Android physical device

Enable **USB debugging** on the device, connect via USB, then:

```bash
flutter devices          # confirm device appears
flutter run -d <device-id>
```

---

### Run on iOS simulator (macOS only)

```bash
open -a Simulator
flutter run -d <simulator-id>
```

---

### Run tests

```bash
# All tests (unit + integration + system)
flutter test

# Single file
flutter test test/unit/backoff_test.dart

# Sequential (avoids port conflicts)
flutter test --concurrency 1
```

---

### Common flutter run commands (while running)

| Key | Action |
|-----|--------|
| `r` | Hot reload |
| `R` | Hot restart |
| `d` | Detach (leave app running) |
| `q` | Quit |
| `h` | Show all commands |

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
