#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)

if [[ -f "$ROOT_DIR/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.env"
  set +a
fi

FLATPAK_DIR="$ROOT_DIR/flatpak"
BUNDLE_SRC="$ROOT_DIR/build/linux/x64/release/bundle"
MANIFEST="$FLATPAK_DIR/com.openfoldr.OpenFoldr.yaml"
BUILD_DIR="$FLATPAK_DIR/.flatpak-builder"
REPO_DIR="$FLATPAK_DIR/repo"
OUTPUT_BUNDLE="$FLATPAK_DIR/OpenFoldr.flatpak"
SIGNING_KEY="${FLATPAK_SIGNING_KEY:-88F23024132C8AD0}"
REPO_URL="${FLATPAK_REPO_URL:-https://example.invalid/openfoldr-repo}"
PUBLIC_KEY_ASC="$FLATPAK_DIR/openfoldr-signing-key.asc"
PUBLIC_KEY_GPG="$FLATPAK_DIR/openfoldr-signing-key.gpg"
FLATPAKREPO_FILE="$FLATPAK_DIR/openfoldr.flatpakrepo"

if ! command -v flutter >/dev/null 2>&1; then
  echo "flutter is required but not found in PATH" >&2
  exit 1
fi

if ! command -v flatpak-builder >/dev/null 2>&1; then
  echo "flatpak-builder is required. Install it first:" >&2
  echo "  sudo dnf install -y flatpak-builder" >&2
  exit 1
fi

if ! command -v flatpak >/dev/null 2>&1; then
  echo "flatpak is required. Install it first:" >&2
  echo "  sudo dnf install -y flatpak" >&2
  exit 1
fi

if ! command -v gpg >/dev/null 2>&1; then
  echo "gpg is required for Flatpak signing. Install it first:" >&2
  echo "  sudo dnf install -y gnupg2" >&2
  exit 1
fi

if ! gpg --list-secret-keys --keyid-format LONG "$SIGNING_KEY" >/dev/null 2>&1; then
  echo "Signing key '$SIGNING_KEY' not found in your GPG keyring." >&2
  echo "Set FLATPAK_SIGNING_KEY to a valid key ID or fingerprint." >&2
  exit 1
fi

if ! flatpak remotes --user --columns=name | grep -qx "flathub"; then
  echo "Adding missing Flatpak remote: flathub"
  flatpak remote-add --user --if-not-exists flathub \
    https://dl.flathub.org/repo/flathub.flatpakrepo
fi

echo "Building Flutter Linux release bundle..."
cd "$ROOT_DIR"
flutter build linux --release

if [[ ! -d "$BUNDLE_SRC" ]]; then
  echo "Expected release bundle not found at: $BUNDLE_SRC" >&2
  exit 1
fi

echo "Preparing Flatpak source bundle..."
rm -rf "$FLATPAK_DIR/bundle"
mkdir -p "$FLATPAK_DIR/bundle"
cp -a "$BUNDLE_SRC"/. "$FLATPAK_DIR/bundle/"

if [[ -f "$ROOT_DIR/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png" ]]; then
  cp "$ROOT_DIR/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png" "$FLATPAK_DIR/com.openfoldr.OpenFoldr.png"
else
  echo "Warning: icon source not found; creating placeholder icon path may fail build." >&2
fi

echo "Building Flatpak repository..."
flatpak-builder \
  --force-clean \
  --user \
  --install-deps-from=flathub \
  --gpg-sign="$SIGNING_KEY" \
  --repo="$REPO_DIR" \
  "$BUILD_DIR" \
  "$MANIFEST"

echo "Updating and signing Flatpak repository metadata..."
flatpak build-update-repo \
  --generate-static-deltas \
  --prune \
  --gpg-sign="$SIGNING_KEY" \
  "$REPO_DIR"

echo "Exporting public signing key..."
gpg --batch --yes --armor --export "$SIGNING_KEY" > "$PUBLIC_KEY_ASC"
gpg --batch --yes --export "$SIGNING_KEY" > "$PUBLIC_KEY_GPG"

echo "Generating flatpak remote descriptor..."
GPG_KEY_BASE64=$(base64 "$PUBLIC_KEY_GPG" | tr -d '\n')
cat > "$FLATPAKREPO_FILE" <<EOF
[Flatpak Repo]
Title=OpenFoldr
Comment=OpenFoldr self-hosted Flatpak repository
Homepage=https://github.com/tumic21/open-foldr
Icon=https://github.com/tumic21/open-foldr/raw/develop/android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png
Url=$REPO_URL
GPGKey=$GPG_KEY_BASE64
EOF

echo "Exporting single-file Flatpak bundle..."
flatpak build-bundle "$REPO_DIR" "$OUTPUT_BUNDLE" com.openfoldr.OpenFoldr

echo "Done. Flatpak bundle created at: $OUTPUT_BUNDLE"
echo "Install with: flatpak install --user --bundle $OUTPUT_BUNDLE"
echo "Public signing keys exported:"
echo "  $PUBLIC_KEY_ASC"
echo "  $PUBLIC_KEY_GPG"
echo "Flatpak remote descriptor generated:"
echo "  $FLATPAKREPO_FILE"

if [[ "$REPO_URL" == "https://example.invalid/openfoldr-repo" ]]; then
  echo "Warning: FLATPAK_REPO_URL is using placeholder value." >&2
  echo "Set FLATPAK_REPO_URL to your hosted repo URL when building for distribution." >&2
fi
