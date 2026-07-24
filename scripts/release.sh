#!/bin/bash
# Supported Talkie release pipeline.
#
# Produces Developer ID-signed, Apple-notarized ZIP and DMG artifacts. It
# intentionally fails closed unless the caller supplies a signing identity,
# team ID, and exactly one supported notarytool credential mechanism.
set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repository_root"

fail() {
  echo "error: $1" >&2
  exit 1
}

on_error() {
  echo "error: supported release pipeline failed; no artifact is ready to publish" >&2
}
trap on_error ERR

usage() {
  cat <<'EOF'
Usage:
  scripts/release.sh
  scripts/release.sh --validate-environment

Required signing environment:
  DEVELOPMENT_TEAM_ID   10-character Apple Developer Team ID
  SIGNING_IDENTITY      Full "Developer ID Application: ..." identity label

Required notarization environment (choose exactly one):
  NOTARY_KEYCHAIN_PROFILE
      notarytool profile previously stored in the macOS Keychain

  NOTARY_KEY_PATH, NOTARY_KEY_ID, NOTARY_ISSUER_ID
      Team App Store Connect API private-key path, key ID, and issuer UUID

The script never prints notarization credential values.
EOF
}

mode="release"
case "${1:-}" in
  "")
    ;;
  --validate-environment)
    mode="validate"
    ;;
  -h|--help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    fail "unknown argument: $1"
    ;;
esac
[[ "$#" -le 1 ]] || fail "only one argument is supported"

: "${DEVELOPMENT_TEAM_ID:?set DEVELOPMENT_TEAM_ID to the 10-character Apple Team ID}"
: "${SIGNING_IDENTITY:?set SIGNING_IDENTITY to the full Developer ID Application identity}"

[[ "$DEVELOPMENT_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] \
  || fail "DEVELOPMENT_TEAM_ID must be a 10-character uppercase Apple Team ID"
[[ "$SIGNING_IDENTITY" == "Developer ID Application: "* ]] \
  || fail "SIGNING_IDENTITY must be a full Developer ID Application identity label"
[[ "$SIGNING_IDENTITY" != "Developer ID Application: " ]] \
  || fail "SIGNING_IDENTITY must include the certificate owner and team"

notary_profile="${NOTARY_KEYCHAIN_PROFILE:-}"
notary_key_path="${NOTARY_KEY_PATH:-}"
notary_key_id="${NOTARY_KEY_ID:-}"
notary_issuer_id="${NOTARY_ISSUER_ID:-}"
api_notary_values=0
[[ -n "$notary_key_path" ]] && ((api_notary_values += 1))
[[ -n "$notary_key_id" ]] && ((api_notary_values += 1))
[[ -n "$notary_issuer_id" ]] && ((api_notary_values += 1))

if [[ -n "$notary_profile" && "$api_notary_values" -ne 0 ]]; then
  fail "choose one notarization credential mechanism, not both"
elif [[ -n "$notary_profile" ]]; then
  notary_auth=(--keychain-profile "$notary_profile")
elif [[ "$api_notary_values" -eq 3 ]]; then
  [[ -r "$notary_key_path" ]] \
    || fail "NOTARY_KEY_PATH must name a readable App Store Connect API private key"
  [[ "$notary_key_id" =~ ^[A-Z0-9]{10,}$ ]] \
    || fail "NOTARY_KEY_ID must be an uppercase alphanumeric App Store Connect key ID"
  [[ "$notary_issuer_id" =~ ^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$ ]] \
    || fail "NOTARY_ISSUER_ID must be an App Store Connect issuer UUID"
  notary_auth=(
    --key "$notary_key_path"
    --key-id "$notary_key_id"
    --issuer "$notary_issuer_id"
  )
elif [[ "$api_notary_values" -ne 0 ]]; then
  fail "set NOTARY_KEY_PATH, NOTARY_KEY_ID, and NOTARY_ISSUER_ID together"
else
  fail "set NOTARY_KEYCHAIN_PROFILE or the three App Store Connect API key variables"
fi

for required_command in \
  codesign ditto git hdiutil shasum spctl xcodebuild xcodegen xcrun
do
  command -v "$required_command" >/dev/null \
    || fail "required command is unavailable: $required_command"
done
[[ -x /usr/libexec/PlistBuddy ]] \
  || fail "required command is unavailable: /usr/libexec/PlistBuddy"

if command -v security >/dev/null; then
  available_identities="$(security find-identity -v -p codesigning 2>/dev/null)" \
    || fail "security could not enumerate code-signing identities"
  grep -Fq "\"$SIGNING_IDENTITY\"" <<< "$available_identities" \
    || fail "SIGNING_IDENTITY was not found in the available code-signing identities"
else
  echo "warning: security is unavailable; signing identity presence could not be preflighted" >&2
fi

if [[ "$mode" == "validate" ]]; then
  echo "Release environment is valid for signing identity: $SIGNING_IDENTITY"
  exit 0
fi

version="$(
  sed -n 's/.*MARKETING_VERSION: *"\([^"]*\)".*/\1/p' project.yml | head -1
)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || fail "could not read a semantic MARKETING_VERSION from project.yml"
deployment_target="$(
  sed -n 's/.*MACOSX_DEPLOYMENT_TARGET: *"\([^"]*\)".*/\1/p' project.yml | head -1
)"
hotkey_version="$(
  sed -n '/^  HotKey:/,/^  FluidAudio:/s/.*exactVersion: *//p' project.yml | head -1
)"
fluid_audio_version="$(
  sed -n '/^  FluidAudio:/,/^settings:/s/.*exactVersion: *//p' project.yml | head -1
)"
[[ -n "$deployment_target" && -n "$hotkey_version" && -n "$fluid_audio_version" ]] \
  || fail "could not resolve release metadata from project.yml"

archive="build/Talkie-supported.xcarchive"
export_dir="build/export-supported"
export_options="build/ExportOptions.resolved.plist"
release_dir="build/release-$version"
dmg_staging="build/dmg-staging-$version"
app="$export_dir/Talkie.app"
zip="$release_dir/Talkie-$version.zip"
dmg="$release_dir/Talkie-$version.dmg"
notary_upload_zip="$release_dir/Talkie-$version-notarization-upload.zip"
app_notary_result="$release_dir/notarization-app.json"
dmg_notary_result="$release_dir/notarization-dmg.json"
checksum_file="$release_dir/SHA256SUMS"

# Only release-specific outputs are removed. Unrelated build products survive.
rm -rf "$archive" "$export_dir" "$release_dir" "$dmg_staging"
rm -f "$export_options"
mkdir -p build "$release_dir"

cleanup() {
  rm -rf "$dmg_staging"
  rm -f "$notary_upload_zip"
}
trap cleanup EXIT

echo "==> Generating project"
xcodegen generate

echo "==> Running portable configuration checks"
scripts/verify-project-config.sh

if grep -Eq 'teamID|__[A-Z0-9_]+__' scripts/ExportOptions.plist; then
  fail "scripts/ExportOptions.plist must not contain a team ID or placeholder"
fi
cp scripts/ExportOptions.plist "$export_options"
/usr/libexec/PlistBuddy \
  -c "Add :teamID string $DEVELOPMENT_TEAM_ID" \
  "$export_options" >/dev/null
/usr/libexec/PlistBuddy -c "Print :teamID" "$export_options" \
  | grep -Fqx "$DEVELOPMENT_TEAM_ID" \
  || fail "resolved export options do not contain the requested team ID"

echo "==> Running release-configuration tests"
xcodebuild test \
  -project Talkie.xcodeproj \
  -scheme Talkie \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData-release \
  -only-testing:TalkieTests/ReleaseConfigurationTests

echo "==> Archiving Talkie $version with Developer ID"
xcodebuild archive \
  -project Talkie.xcodeproj \
  -scheme Talkie \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$archive" \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM_ID" \
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY"

echo "==> Exporting the Developer ID application"
xcodebuild -exportArchive \
  -archivePath "$archive" \
  -exportOptionsPlist "$export_options" \
  -exportPath "$export_dir" \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM_ID" \
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY"

[[ -d "$app" ]] || fail "Xcode export did not produce $app"
for legal_notice in LICENSE NOTICE THIRD_PARTY_NOTICES.txt; do
  [[ -f "$app/Contents/Resources/$legal_notice" ]] \
    || fail "exported app is missing legal notice: $legal_notice"
done

echo "==> Verifying the pre-notarization Developer ID signature"
codesign --verify --deep --strict --verbose=2 "$app"

submit_for_notarization() {
  local artifact="$1"
  local result_file="$2"
  local artifact_label="$3"
  local notary_exit=0

  xcrun notarytool submit "$artifact" \
    "${notary_auth[@]}" \
    --wait \
    --output-format json \
    --no-progress > "$result_file" || notary_exit=$?

  submitted_status="$(
    /usr/bin/plutil -extract status raw "$result_file" 2>/dev/null || true
  )"
  submitted_request_id="$(
    /usr/bin/plutil -extract id raw "$result_file" 2>/dev/null || true
  )"
  if [[ "$notary_exit" -ne 0 || "$submitted_status" != "Accepted" ]]; then
    [[ -n "$submitted_status" ]] || submitted_status="Unknown"
    fail "Apple notarization did not return Accepted for $artifact_label (status: $submitted_status)"
  fi
}

echo "==> Submitting the Developer ID app to Apple notarization"
ditto -c -k --keepParent "$app" "$notary_upload_zip"
submit_for_notarization "$notary_upload_zip" "$app_notary_result" "the app upload"
app_notary_status="$submitted_status"
app_notary_request_id="$submitted_request_id"

echo "==> Stapling and validating the app ticket"
xcrun stapler staple "$app"
codesign --verify --deep --strict --verbose=2 "$app"
spctl -a -vv --type execute "$app"
xcrun stapler validate "$app"

echo "==> Packaging the final ZIP from the stapled app"
ditto -c -k --keepParent "$app" "$zip"

echo "==> Building the final DMG around the stapled app"
mkdir -p "$dmg_staging"
cp -R "$app" "$dmg_staging/"
ln -s /Applications "$dmg_staging/Applications"
hdiutil create \
  -volname Talkie \
  -srcfolder "$dmg_staging" \
  -format UDZO \
  -ov \
  "$dmg"

echo "==> Submitting the exact DMG to Apple notarization"
submit_for_notarization "$dmg" "$dmg_notary_result" "the final DMG"
dmg_notary_status="$submitted_status"
dmg_notary_request_id="$submitted_request_id"

echo "==> Stapling the DMG ticket"
xcrun stapler staple "$dmg"

echo "==> Verifying the supported signed artifacts"
codesign --verify --deep --strict --verbose=2 "$app"
spctl -a -vv --type execute "$app"
xcrun stapler validate "$app"
xcrun stapler validate "$dmg"
spctl -a -vv --type open "$dmg"

echo "==> Generating and verifying deterministic checksums"
(
  cd "$release_dir"
  shasum -a 256 "$(basename "$dmg")" "$(basename "$zip")" \
    | LC_ALL=C sort -k2 > "$(basename "$checksum_file")"
  shasum -a 256 -c "$(basename "$checksum_file")"
)

commit_sha="$(git rev-parse HEAD)"
xcode_version="$(xcodebuild -version)"

echo
echo "Supported release metadata:"
echo "  Tag / version: v$version / $version"
echo "  Commit: $commit_sha"
while IFS= read -r version_line; do
  echo "  Xcode: $version_line"
done <<< "$xcode_version"
echo "  macOS deployment target: $deployment_target"
echo "  Dependencies: HotKey $hotkey_version; FluidAudio $fluid_audio_version"
echo "  Signing identity: $SIGNING_IDENTITY"
echo "  App notarization status: $app_notary_status"
[[ -n "$app_notary_request_id" ]] \
  && echo "  App notarization request ID: $app_notary_request_id"
echo "  DMG notarization status: $dmg_notary_status"
[[ -n "$dmg_notary_request_id" ]] \
  && echo "  DMG notarization request ID: $dmg_notary_request_id"
echo "  DMG: $dmg"
echo "  ZIP: $zip"
echo "  Checksums: $checksum_file"
