#!/bin/bash
# Builds build/SimpleScanner.app; a release build is also installed into /Applications (INSTALL=0 to skip).
# Usage: Scripts/bundle.sh [debug|release]   (default: release)
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
VERSION="0.9.0"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

if [ ! -f Resources/AppIcon.icns ]; then
    swift Scripts/make-icon.swift
fi

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)"
APP="${APP:-build/SimpleScanner.app}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/SimpleScanner" "$APP/Contents/MacOS/SimpleScanner"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# The vendor index is read from Contents/Resources (see OUILookup.candidateURLs), not from a SwiftPM bundle.
cp Sources/SimpleScannerCore/Resources/vendors.json "$APP/Contents/Resources/vendors.json"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>SimpleScanner</string>
    <key>CFBundleDisplayName</key><string>SimpleScanner</string>
    <key>CFBundleIdentifier</key><string>net.cieadrienm.simplescanner</string>
    <key>CFBundleExecutable</key><string>SimpleScanner</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>@VERSION@</string>
    <key>CFBundleVersion</key><string>@BUILD@</string>
    <key>CFBundleDevelopmentRegion</key><string>fr</string>
    <key>CFBundleLocalizations</key><array><string>fr</string><string>en</string></array>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHumanReadableCopyright</key><string>cie Adrien M — Compagnie Adrien M · issu d'iPScanner (MIT)</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>SimpleScanner découvre les appareils de votre réseau local par ping ICMP, table ARP, sondes TCP et Bonjour.</string>
    <key>NSBonjourServices</key>
    <array>
        <string>_airplay._tcp</string><string>_raop._tcp</string><string>_googlecast._tcp</string>
        <string>_companion-link._tcp</string><string>_homekit._tcp</string><string>_hap._tcp</string>
        <string>_smb._tcp</string><string>_afpovertcp._tcp</string><string>_nfs._tcp</string>
        <string>_ssh._tcp</string><string>_sftp-ssh._tcp</string><string>_rfb._tcp</string>
        <string>_workstation._tcp</string><string>_http._tcp</string><string>_https._tcp</string>
        <string>_ipp._tcp</string><string>_ipps._tcp</string><string>_printer._tcp</string>
        <string>_pdl-datastream._tcp</string><string>_scanner._tcp</string><string>_spotify-connect._tcp</string>
        <string>_sonos._tcp</string><string>_hue._tcp</string><string>_osc._udp</string>
        <string>_oscjson._tcp</string><string>_ndi._tcp</string><string>_device-info._tcp</string>
    </array>
    <key>UTExportedTypeDeclarations</key>
    <array>
        <dict>
            <key>UTTypeIdentifier</key><string>net.cieadrienm.simplescan</string>
            <key>UTTypeDescription</key><string>Scan SimpleScanner</string>
            <key>UTTypeConformsTo</key><array><string>public.json</string></array>
            <key>UTTypeTagSpecification</key>
            <dict><key>public.filename-extension</key><array><string>simplescan</string></array></dict>
        </dict>
    </array>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Scan SimpleScanner</string>
            <key>CFBundleTypeRole</key><string>Editor</string>
            <key>LSHandlerRank</key><string>Owner</string>
            <key>LSItemContentTypes</key><array><string>net.cieadrienm.simplescan</string></array>
        </dict>
    </array>
</dict>
</plist>
PLIST
sed -i '' -e "s/@VERSION@/$VERSION/" -e "s/@BUILD@/$BUILD/" "$APP/Contents/Info.plist"

if [ -z "${SIGN_IDENTITY:-}" ]; then
    IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
    SIGN_IDENTITY="$(echo "$IDENTITIES" | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)"
    [ -n "$SIGN_IDENTITY" ] || SIGN_IDENTITY="$(echo "$IDENTITIES" | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)"
    [ -n "$SIGN_IDENTITY" ] || SIGN_IDENTITY="-"
fi
# A stable signature keeps the Local Network permission macOS grants the app from one build to the next.
if ! codesign --force --timestamp=none --sign "$SIGN_IDENTITY" "$APP" 2>/tmp/simplescanner-codesign.log; then
    echo "warning: signing with '$SIGN_IDENTITY' failed; falling back to ad hoc" >&2
    SIGN_IDENTITY="-"
    codesign --force --sign - "$APP"
fi
echo "signed: $SIGN_IDENTITY" >&2

INSTALL_DIR="${INSTALL_DIR:-/Applications}"
if [ "${INSTALL:-$([ "$CONFIG" = release ] && echo 1 || echo 0)}" = 1 ]; then
    TARGET="$INSTALL_DIR/SimpleScanner.app"
    if pgrep -f "$TARGET/Contents/MacOS/SimpleScanner" >/dev/null; then
        echo "note: SimpleScanner is running from $TARGET — quit and reopen it to get this build" >&2
    fi
    rm -rf "$TARGET.new"
    ditto "$APP" "$TARGET.new"
    rm -rf "$TARGET"
    mv "$TARGET.new" "$TARGET"
    echo "installed: $TARGET" >&2
fi
echo "$APP"
