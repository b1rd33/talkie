#!/bin/bash
# Talkie release pipeline: archive → Developer ID export → verify → notarize →
# staple → DMG + zip. Safe to re-run; wipes build/ first. (Paid Developer-ID
# path; the free, account-less path is scripts/build-release-adhoc.sh.)
#
# One-time setup (⚠️ HUMAN — requires a paid Apple Developer account):
#   1. "Developer ID Application" certificate in the login keychain
#   2. xcrun notarytool store-credentials talkie-notary \
#        --apple-id <appleID> --team-id <teamID> --password <app-specific password>
#   3. Export DEVELOPMENT_TEAM=<10-character Apple Team ID> for this invocation
set -euo pipefail
cd "$(dirname "$0")/.."

: "${DEVELOPMENT_TEAM:?set DEVELOPMENT_TEAM to the 10-character Apple Team ID}"
if [[ ! "$DEVELOPMENT_TEAM" =~ ^[A-Z0-9]{10}$ ]]; then
  echo "error: DEVELOPMENT_TEAM must be a 10-character uppercase Apple Team ID" >&2
  exit 1
fi

VERSION="$(sed -n 's/.*MARKETING_VERSION: *"\([^"]*\)".*/\1/p' project.yml | head -1)"
if [ -z "$VERSION" ]; then
  echo "error: could not read MARKETING_VERSION from project.yml" >&2
  exit 1
fi

NOTARY_PROFILE="${NOTARY_PROFILE:-talkie-notary}"
ARCHIVE="build/Talkie.xcarchive"
EXPORT_DIR="build/export"
EXPORT_OPTIONS="build/ExportOptions.local.plist"
APP="$EXPORT_DIR/Talkie.app"
ZIP="build/Talkie-$VERSION.zip"
DMG="build/Talkie-$VERSION.dmg"

rm -rf build

echo "==> Generating project"
xcodegen generate

echo "==> Running portable configuration checks"
scripts/verify-project-config.sh

mkdir -p "$(dirname "$EXPORT_OPTIONS")"
sed "s/__DEVELOPMENT_TEAM__/$DEVELOPMENT_TEAM/" \
  scripts/ExportOptions.plist > "$EXPORT_OPTIONS"

echo "==> Running deterministic logic suite"
xcodebuild test \
  -project Talkie.xcodeproj \
  -scheme Talkie \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData

echo "==> Archiving Talkie $VERSION (Release)"
xcodebuild archive \
  -project Talkie.xcodeproj \
  -scheme Talkie \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM"

echo "==> Exporting with Developer ID"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$EXPORT_OPTIONS" \
  -exportPath "$EXPORT_DIR"

echo "==> Verifying code signature"
codesign --verify --deep --strict --verbose=2 "$APP"
codesign -d --entitlements :- "$APP" > build/entitlements.plist

echo "==> Notarizing (waits on Apple, typically 1-10 minutes)"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapling and verifying"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl -a -vv "$APP"

echo "==> Launch smoke check"
open -gj "$APP"
sleep 3
pgrep -x Talkie >/dev/null
pkill -x Talkie

echo "==> Re-zipping the stapled app"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

echo "==> Building DMG"
STAGING="build/dmg-staging"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname Talkie -srcfolder "$STAGING" -format UDZO -ov "$DMG"

echo ""
echo "Release artifacts:"
echo "  Download (DMG):  $DMG"
echo "  Download (zip):  $ZIP"
echo ""
echo "Attach one to a GitHub Release. Updates are manual (no auto-update)."
