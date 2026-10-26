#!/bin/bash
# Packages a release build of SimpleScanner into build/SimpleScanner-<version>.zip,
# computes its SHA-256 digest, and prints the JSON manifest entry for SimpleUpdater.
set -euo pipefail
cd "$(dirname "$0")/.."

./Scripts/bundle.sh release

APP="build/SimpleScanner.app"
PLIST="$APP/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
ZIP="build/SimpleScanner-${VERSION}.zip"

rm -f "$ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"

SHA256="$(shasum -a 256 "$ZIP" | awk '{print $1}')"
REPO="${GITHUB_REPO:-cieadrienm/SimpleScanner}"
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/v${VERSION}/SimpleScanner-${VERSION}.zip"

echo ""
echo "=== Release Archive ==="
echo "App:     $APP"
echo "Zip:     $ZIP"
echo "Version: $VERSION (build $BUILD)"
echo "SHA-256: $SHA256"
echo ""
echo "=== JSON Manifest Snippet ==="
cat <<EOF
{
  "net.cieadrienm.simplescanner": {
    "version": "$VERSION",
    "build": $BUILD,
    "url": "$DOWNLOAD_URL",
    "sha256": "$SHA256",
    "notes_fr": "Mise à jour de SimpleScanner $VERSION.",
    "notes_en": "SimpleScanner $VERSION update."
  }
}
EOF
