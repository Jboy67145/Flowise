#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! command -v pnpm >/dev/null 2>&1; then
    echo "pnpm is required but was not found in PATH" >&2
    exit 1
fi

VERSION_ARG="${1:-}"
SKIP_BUILD="${RELEASE_ZIP_SKIP_BUILD:-0}"

ROOT_VERSION="$(node -p "require('./package.json').version")"
VERSION="${VERSION_ARG:-$ROOT_VERSION}"
VERSION="${VERSION#v}"
TAG="v${VERSION}"

RELEASE_DIR="dist/releases"
STAGING_ROOT="dist/.release-staging"
BUNDLE_NAME="flowise-${VERSION}"
BUNDLE_DIR="${STAGING_ROOT}/${BUNDLE_NAME}"
ZIP_PATH="${RELEASE_DIR}/${BUNDLE_NAME}.zip"
CHECKSUM_PATH="${ZIP_PATH}.sha256"
NOTES_PATH="${RELEASE_DIR}/${BUNDLE_NAME}-release-notes.md"

BUILD_ORDER=(
    "flowise-components"
    "flowise-ui"
    "flowise"
)

if [[ "$SKIP_BUILD" != "1" ]]; then
    echo "Building packages in deterministic order: ${BUILD_ORDER[*]}"
    pnpm --filter flowise-components build
    pnpm --filter flowise-ui build
    pnpm --filter flowise build
else
    echo "Skipping package builds because RELEASE_ZIP_SKIP_BUILD=1"
fi

rm -rf "$STAGING_ROOT"
mkdir -p "$BUNDLE_DIR" "$RELEASE_DIR"

copy_into_bundle() {
    local src_path="$1"
    local dest_path="$2"

    if [[ ! -e "$src_path" ]]; then
        echo "Missing required path: $src_path" >&2
        exit 1
    fi

    mkdir -p "$(dirname "${BUNDLE_DIR}/${dest_path}")"
    cp -R "$src_path" "${BUNDLE_DIR}/${dest_path}"
}

copy_into_bundle package.json package.json
copy_into_bundle pnpm-lock.yaml pnpm-lock.yaml
copy_into_bundle README.md README.md
copy_into_bundle LICENSE.md LICENSE.md
copy_into_bundle assets assets
copy_into_bundle packages/components/dist packages/components/dist
copy_into_bundle packages/components/package.json packages/components/package.json
copy_into_bundle packages/ui/dist packages/ui/dist
copy_into_bundle packages/ui/package.json packages/ui/package.json
copy_into_bundle packages/ui/.env.example packages/ui/.env.example
copy_into_bundle packages/server/bin packages/server/bin
copy_into_bundle packages/server/dist packages/server/dist
copy_into_bundle packages/server/marketplaces packages/server/marketplaces
copy_into_bundle packages/server/package.json packages/server/package.json
copy_into_bundle packages/server/.env.example packages/server/.env.example
copy_into_bundle packages/server/oauth2.html packages/server/oauth2.html

SOURCE_DATE_EPOCH="$(git log -1 --format=%ct)"
find "$STAGING_ROOT" -exec touch -h -d "@${SOURCE_DATE_EPOCH}" {} +

rm -f "$ZIP_PATH"
(
    cd "$STAGING_ROOT"
    find "$BUNDLE_NAME" -type f | LC_ALL=C sort | zip -X -q "$ROOT_DIR/$ZIP_PATH" -@
)

CHECKSUM="$(sha256sum "$ZIP_PATH" | awk '{print $1}')"
printf '%s  %s\n' "$CHECKSUM" "$(basename "$ZIP_PATH")" > "$CHECKSUM_PATH"

BUILD_UTC="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
cat > "$NOTES_PATH" <<NOTES
# Flowise ${TAG} release bundle

- Tag: ${TAG}
- Version: ${VERSION}
- Built at (UTC): ${BUILD_UTC}
- Source date epoch: ${SOURCE_DATE_EPOCH}
- Build order:
  1. flowise-components
  2. flowise-ui
  3. flowise
- Archive: $(basename "$ZIP_PATH")
- SHA256: ${CHECKSUM}

## Included runtime assets and config templates

- Root: package metadata, lockfile, README, LICENSE, assets/
- packages/components: dist/, package.json
- packages/ui: dist/, package.json, .env.example
- packages/server: bin/, dist/, marketplaces/, package.json, .env.example, oauth2.html
NOTES

echo "Release zip created: $ZIP_PATH"
echo "Checksum written: $CHECKSUM_PATH"
echo "Release notes written: $NOTES_PATH"
