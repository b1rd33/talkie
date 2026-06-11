#!/bin/bash
# Talkie release pipeline: archive → Developer ID export → verify → notarize →
# staple → DMG + Sparkle zip. Safe to re-run; wipes build/ first.
#
# One-time setup (⚠️ HUMAN — docs/release-checklist.md "One-time setup"):
#   1. "Developer ID Application" certificate in the login keychain
#   2. xcrun notarytool store-credentials talkie-notary \
#        --apple-id <appleID> --team-id <teamID> --password <app-specific password>
#   3. Real teamID in scripts/ExportOptions.plist and DEVELOPMENT_TEAM in project.yml
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(sed -n 's/.*MARKETING_VERSION: *"\([^"]*\)".*/\1/p' project.yml | head -1)"
if [ -z "$VERSION" ]; then
  echo "error: could not read MARKETING_VERSION from project.yml" >&2
  exit 1
fi

NOTARY_PROFILE="${NOTARY_PROFILE:-talkie-notary}"
ARCHIVE="build/Talkie.xcarchive"
EXPORT_DIR="build/export"
APP="$EXPORT_DIR/Talkie.app"
ZIP="build/Talkie-$VERSION.zip"
DMG="build/Talkie-$VERSION.dmg"

rm -rf build

echo "==> Generating project"
xcodegen generate

echo "==> Archiving Talkie $VERSION (Release)"
xcodebuild archive \
  -project Talkie.xcodeproj \
  -scheme Talkie \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE"

echo "==> Exporting with Developer ID"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist scripts/ExportOptions.plist \
  -exportPath "$EXPORT_DIR"

echo "==> Verifying code signature"
codesign --verify --deep --strict --verbose=2 "$APP"

echo "==> Notarizing (waits on Apple, typically 1-10 minutes)"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

echo "==> Stapling and verifying"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
spctl -a -vv "$APP"

echo "==> Re-zipping the stapled app (this zip feeds the Sparkle appcast)"
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
echo "  Website download:  $DMG"
echo "  Sparkle update:    $ZIP"
echo ""
echo "Appcast: copy the zip into your updates folder and run Sparkle's"
echo "generate_appcast over it (signs with the EdDSA key from the Keychain),"
echo "then upload appcast.xml + zip to the SUFeedURL host."
echo "Exact commands: docs/release-checklist.md step 6."
