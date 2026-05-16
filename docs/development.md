# Development Guide

This page contains contributor-focused setup, run, and test instructions.

## Prerequisites

- Flutter SDK (stable): https://flutter.dev/docs/get-started/install
- Dart (bundled with Flutter)
- Android development: Android SDK, emulator or physical device
- Linux desktop builds: CMake, Ninja, clang, pkg-config
- Windows desktop builds: Visual Studio 2022 with C++ workload

Install project dependencies:

```bash
flutter pub get
```

## Run Locally

### Linux (desktop)

```bash
flutter run -d linux
```

### Windows (desktop)

```bash
flutter run -d windows
```

### Android emulator

List and launch an emulator:

```bash
~/Android/Sdk/emulator/emulator -list-avds
~/Android/Sdk/emulator/emulator -avd <avd-name> -no-snapshot-save
```

Run app:

```bash
flutter run -d emulator-5554
```

Verbose output:

```bash
flutter run -v -d emulator-5554
```

### Android physical device

Enable USB debugging, connect the device, then run:

```bash
flutter devices
flutter run -d <device-id>
```

### iOS simulator (macOS only)

```bash
open -a Simulator
flutter run -d <simulator-id>
```

## Run Tests

Run all tests:

```bash
flutter test
```

Run a single test file:

```bash
flutter test test/unit/backoff_test.dart
```

Run tests sequentially (useful to avoid port conflicts):

```bash
flutter test --concurrency 1
```

## Helpful flutter run Keys

- r: hot reload
- R: hot restart
- d: detach app and keep it running
- q: quit
- h: show command help

## Branching Strategy

- develop is the active integration branch for day-to-day work.
- main is the stable branch for release milestones.
- Feature branches should branch from develop and merge back via pull requests.
- Release pull requests should merge develop into main.

