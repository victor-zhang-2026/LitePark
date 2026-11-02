#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
./scripts/build-app.sh
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' .build/LitePark.app/Contents/Info.plist)"
OUTPUT="$PWD/dist/LitePark-v${VERSION}-macOS.zip"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/litepark-release.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

mkdir -p "$PWD/dist"
ditto --norsrc ".build/LitePark.app" "$STAGE/LitePark.app"

# Preserve the build signature so the download matches the installed app.
# Local-development and ad-hoc builds are not Apple-notarized.
codesign --verify --deep --strict "$STAGE/LitePark.app"
ditto -c -k --norsrc --keepParent "$STAGE/LitePark.app" "$OUTPUT"

echo "$OUTPUT"
