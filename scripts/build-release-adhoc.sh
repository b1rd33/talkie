#!/bin/bash
# Talkie FREE distribution build (no Apple Developer account).
#
# Produces an ad-hoc-signed, NOT-notarized zip you can attach to a GitHub
# Release and share. Friends do a one-time "Open Anyway" (docs/install-free.md).
# This does NOT touch the paid Developer-ID pipeline (scripts/release.sh).
#
# Why ad-hoc + hardened-runtime-off (ReleaseAdhoc config): without a Developer
# ID cert the embedded frameworks (FluidAudio/HotKey) can only be
# ad-hoc signed, and hardened runtime's library validation would refuse to load
# them. Hardened runtime only matters paired with notarization (impossible here).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(sed -n 's/.*MARKETING_VERSION: *"\([^"]*\)".*/\1/p' project.yml | head -1)"
[ -n "$VERSION" ] || { echo "error: could not read MARKETING_VERSION from project.yml" >&2; exit 1; }

ARCHIVE="build/Talkie-adhoc.xcarchive"
APP_SRC="$ARCHIVE/Products/Applications/Talkie.app"
EXPORT_DIR="build/export-adhoc"
APP="$EXPORT_DIR/Talkie.app"
ZIP="build/Talkie-$VERSION-adhoc.zip"

rm -rf build/Talkie-adhoc.xcarchive "$EXPORT_DIR" "$ZIP"

echo "==> Generating project"
xcodegen generate

echo "==> Archiving Talkie $VERSION (ReleaseAdhoc, ad-hoc signed)"
xcodebuild archive \
  -project Talkie.xcodeproj \
  -scheme Talkie \
  -configuration ReleaseAdhoc \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE"

echo "==> Copying app out of the archive (no -exportArchive: ad-hoc export is unreliable)"
mkdir -p "$EXPORT_DIR"
cp -R "$APP_SRC" "$APP"

# Re-sign inside-out so every nested framework/helper/dylib carries a valid
# ad-hoc seal before the outer app. Deepest paths first; no --options runtime.
echo "==> Re-signing inside-out (ad-hoc)"
while IFS= read -r item; do
  codesign --force --timestamp=none -s - "$item"
done < <(find "$APP/Contents" \( -name "*.framework" -o -name "*.xpc" -o -name "*.app" -o -name "*.dylib" \) -print | awk '{ print length, $0 }' | sort -rn | cut -d' ' -f2-)
codesign --force --timestamp=none -s - "$APP"

echo "==> Verifying the seal (DR is a cdhash anchor for ad-hoc — that's expected)"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> Packaging (ditto --keepParent preserves the seal across zip/unzip)"
ditto -c -k --keepParent "$APP" "$ZIP"

echo ""
echo "Built: $ZIP"
echo "NOTE: ad-hoc signed, NOT notarized — 'spctl -a' WILL reject (expected)."
echo "      Friends use the one-time Privacy & Security override (docs/install-free.md)."
echo "      Upload $ZIP to a GitHub Release and share the link."
