#!/bin/bash
# Packages a release build of SimpleScanner (Universal arm64+x86_64 and Intel x86_64)
# into build/SimpleScanner-<version>.zip and build/SimpleScanner-<version>-intel-x86_64.zip,
# computes their SHA-256 digests, and prints the JSON manifest entry for SimpleUpdater.
set -euo pipefail
cd "$(dirname "$0")/.."

ARCH=universal ./Scripts/bundle.sh release

APP="build/SimpleScanner.app"
PLIST="$APP/Contents/Info.plist"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
ZIP="build/SimpleScanner-${VERSION}.zip"
INTEL_APP="build/SimpleScanner-Intel/SimpleScanner.app"
INTEL_ZIP="build/SimpleScanner-${VERSION}-intel-x86_64.zip"

rm -f "$ZIP" "$INTEL_ZIP"
ditto -c -k --sequesterRsrc --keepParent "$APP" "$ZIP"
SHA256="$(shasum -a 256 "$ZIP" | awk '{print $1}')"

ARCH=x86_64 INSTALL=0 APP="$INTEL_APP" ./Scripts/bundle.sh release >/dev/null
ditto -c -k --sequesterRsrc --keepParent "$INTEL_APP" "$INTEL_ZIP"
INTEL_SHA256="$(shasum -a 256 "$INTEL_ZIP" | awk '{print $1}')"

REPO="${GITHUB_REPO:-cieadrienm/SimpleScanner}"
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/v${VERSION}/SimpleScanner-${VERSION}.zip"

echo ""
echo "=== Release Archives ==="
echo "Universal App: $APP ($(lipo -archs "$APP/Contents/MacOS/SimpleScanner"))"
echo "Universal Zip: $ZIP"
echo "  SHA-256:     $SHA256"
echo "Intel App:     $INTEL_APP ($(lipo -archs "$INTEL_APP/Contents/MacOS/SimpleScanner"))"
echo "Intel Zip:     $INTEL_ZIP"
echo "  SHA-256:     $INTEL_SHA256"
echo "Version:       $VERSION (build $BUILD)"
echo ""
echo "=== JSON Manifest Snippet ==="
cat <<EOF
{
  "net.cieadrienm.simplescanner": {
    "version": "$VERSION",
    "build": $BUILD,
    "url": "$DOWNLOAD_URL",
    "sha256": "$SHA256",
    "notes_fr": "Mise à jour de SimpleScanner $VERSION (Universal Apple Silicon + Intel).",
    "notes_en": "SimpleScanner $VERSION update (Universal Apple Silicon + Intel)."
  }
}
EOF
