#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd)

if [[ -f "$ROOT_DIR/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT_DIR/.env"
  set +a
fi

FLATPAK_DEPLOY_HOST="${FLATPAK_DEPLOY_HOST:-}"
FLATPAK_DEPLOY_PATH="${FLATPAK_DEPLOY_PATH:-}"

if [[ -z "$FLATPAK_DEPLOY_HOST" || -z "$FLATPAK_DEPLOY_PATH" ]]; then
  echo "ERROR: FLATPAK_DEPLOY_HOST and FLATPAK_DEPLOY_PATH must be set in .env"
  exit 1
fi

REPO_DIR="$ROOT_DIR/flatpak/repo"
FLATPAKREPO_FILE="$ROOT_DIR/flatpak/openfoldr.flatpakrepo"
PUBLIC_KEY_ASC="$ROOT_DIR/flatpak/openfoldr-signing-key.asc"
PUBLIC_KEY_GPG="$ROOT_DIR/flatpak/openfoldr-signing-key.gpg"

if [[ ! -d "$REPO_DIR" ]]; then
  echo "ERROR: flatpak/repo/ not found — run build-flatpak.sh first"
  exit 1
fi

echo "==> Deploying Flatpak repo to $FLATPAK_DEPLOY_HOST:$FLATPAK_DEPLOY_PATH"

# Ensure remote directory exists
ssh "$FLATPAK_DEPLOY_HOST" "mkdir -p '$FLATPAK_DEPLOY_PATH'"

# Sync repo (delete stale files on remote)
rsync -avz --delete "$REPO_DIR/" "$FLATPAK_DEPLOY_HOST:$FLATPAK_DEPLOY_PATH/repo/"

# Upload .flatpakrepo descriptor if it exists
if [[ -f "$FLATPAKREPO_FILE" ]]; then
  rsync -avz "$FLATPAKREPO_FILE" "$FLATPAK_DEPLOY_HOST:$FLATPAK_DEPLOY_PATH/openfoldr.flatpakrepo"
fi

# Upload public signing keys for manual key import on clients
if [[ -f "$PUBLIC_KEY_ASC" ]]; then
  rsync -avz "$PUBLIC_KEY_ASC" "$FLATPAK_DEPLOY_HOST:$FLATPAK_DEPLOY_PATH/openfoldr-signing-key.asc"
fi
if [[ -f "$PUBLIC_KEY_GPG" ]]; then
  rsync -avz "$PUBLIC_KEY_GPG" "$FLATPAK_DEPLOY_HOST:$FLATPAK_DEPLOY_PATH/openfoldr-signing-key.gpg"
fi

echo "==> Deploy complete."
echo "    Repo URL:        ${FLATPAK_REPO_URL:-<set FLATPAK_REPO_URL in .env>}"
echo "    .flatpakrepo:    ${FLATPAK_REPO_URL%/repo}/openfoldr.flatpakrepo"
echo "    Public key:      ${FLATPAK_REPO_URL%/repo}/openfoldr-signing-key.asc"
