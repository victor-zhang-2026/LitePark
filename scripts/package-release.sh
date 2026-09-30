#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
VERSION="1.0.0"
OUTPUT="$PWD/dist/LitePark-v${VERSION}-macOS.zip"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/litepark-release.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

./scripts/build-app.sh
mkdir -p "$PWD/dist"
ditto --norsrc ".build/LitePark.app" "$STAGE/LitePark.app"

# The public v1.0.0 package is ad-hoc signed. A local development certificate
# must not be shipped as though it were an Apple Developer ID signature.
codesign --force --deep --sign - "$STAGE/LitePark.app"
ditto -c -k --norsrc --keepParent "$STAGE/LitePark.app" "$OUTPUT"

echo "$OUTPUT"
