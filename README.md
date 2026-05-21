# OpenFoldr

![Linux Flatpak Stable](https://img.shields.io/badge/Linux%20Flatpak-Stable-2ea44f)
![Android APK Stable](https://img.shields.io/badge/Android%20APK-Stable-2ea44f)
![Windows Installer Stable](https://img.shields.io/badge/Windows%20Installer-Stable-2ea44f)
![Windows Portable Stable](https://img.shields.io/badge/Windows%20Portable-Stable-2ea44f)

OpenFoldr is a cross-platform app for sharing folders on your local network.

It is designed for fast LAN collaboration with controlled access and safer file operations.

## Download

Download the latest build from GitHub Releases:

- https://github.com/tumic21/open-foldr/releases

Release assets currently include:

- Linux Flatpak bundle: `openfoldr-<version>-linux.flatpak`
- Android APK: `openfoldr-<version>-android.apk`
- Windows installer: `openfoldr-<version>-windows-setup.exe`
- Windows portable ZIP: `openfoldr-<version>-windows-portable.zip`

## Supported Platforms

| Platform | Package | Status |
|---|---|---|
| Linux | Flatpak (`.flatpak`) | Stable |
| Android | APK (`.apk`) | Stable |
| Windows | Installer (`.exe`) | Stable |
| Windows | Portable ZIP (`.zip`) | Stable |

## Install And Run

### Linux (Flatpak)

1. Download the `.flatpak` asset from the latest release.
2. Install it:

```bash
flatpak install --user --bundle ./openfoldr-<version>-linux.flatpak
```

3. Run it:

```bash
flatpak run com.openfoldr.OpenFoldr
```

### Android (APK)

1. Download the `.apk` asset from the latest release.
2. On your Android device, allow installs from the source app (browser/files app).
3. Open the APK and complete installation.

### Windows (Installer)

1. Download the installer `.exe` asset from the latest release.
2. Run the installer and follow the setup wizard.
3. Start OpenFoldr from the Start menu or desktop shortcut.

### Windows (Portable ZIP)

1. Download the `.zip` asset from the latest release.
2. Extract it to any folder.
3. Run `open_foldr.exe`.

## Quick Start

1. Open OpenFoldr on two devices in the same local network.
2. On one device, start sharing a folder.
3. On the other device, connect to the host and browse or transfer files.

## Screenshots

### Desktop

| Home screen | Host session |
|---|---|
| ![Desktop: home screen](screenshots/Screenshot_20260519_094659.png) | ![Desktop: active host session](screenshots/Screenshot_20260519_094733.png) |

| Join share | File manager list |
|---|---|
| ![Desktop: join a share](screenshots/Screenshot_20260519_105110.png) | ![Desktop: file manager list view](screenshots/Screenshot_20260519_110251.png) |

### Android

| Home screen | Connect and roots |
|---|---|
| <img src="screenshots/Screenshot_20260521_083942.jpg" alt="Android: home screen" width="260" /> | <img src="screenshots/Screenshot_20260520_091453.jpg" alt="Android: connected roots" width="260" /> |

| Grid view | Image preview |
|---|---|
| <img src="screenshots/Screenshot_20260520_151216.jpg" alt="Android: file manager grid" width="260" /> | <img src="screenshots/Screenshot_20260520_091519.jpg" alt="Android: image preview" width="260" /> |

## Troubleshooting

- Ensure both devices are on the same LAN.
- Allow OpenFoldr through firewall prompts when asked.
- If automatic discovery fails, connect manually using the host address.

## For Developers

- Development and local run instructions: [docs/development.md](docs/development.md)
- Security reporting: [SECURITY.md](SECURITY.md)

## License

Licensed under Apache License 2.0.
