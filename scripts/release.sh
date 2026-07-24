#!/bin/bash
# Fail-closed supported release: provenance → Developer ID → notarization →
# packaged-artifact verification → atomic promotion.
set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repository_root"

staging_root=""
mounted_path=""
history_result=""

fail() {
  echo "error: $1" >&2
  exit 1
}

cleanup() {
  local status=$?
  set +e
  if [[ -n "$mounted_path" ]]; then
    hdiutil detach "$mounted_path" >/dev/null 2>&1
  fi
  [[ -n "$staging_root" ]] && rm -rf "$staging_root"
  [[ -n "$history_result" ]] && rm -f "$history_result"
  if [[ "$status" -ne 0 ]]; then
    echo "error: supported release failed; no staged artifact is publishable" >&2
  fi
  trap - EXIT
  exit "$status"
}
trap cleanup EXIT

usage() {
  cat <<'EOF'
Usage:
  scripts/release.sh
  scripts/release.sh --validate-environment

Required signing environment:
  DEVELOPMENT_TEAM_ID   10-character Apple Developer Team ID
  SIGNING_IDENTITY      Full "Developer ID Application: ... (TEAMID)" label

Required notarization environment (choose exactly one):
  NOTARY_KEYCHAIN_PROFILE
  NOTARY_KEY_PATH, NOTARY_KEY_ID, NOTARY_ISSUER_ID

Environment validation makes an authenticated Apple network request using
`notarytool history`. Credential values are never printed.
EOF
}

mode="release"
case "${1:-}" in
  "") ;;
  --validate-environment) mode="validate" ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; fail "unknown argument: $1" ;;
esac
[[ "$#" -le 1 ]] || fail "only one argument is supported"

[[ -n "${DEVELOPMENT_TEAM_ID:-}" ]] \
  || fail "set DEVELOPMENT_TEAM_ID to the 10-character Apple Team ID"
[[ -n "${SIGNING_IDENTITY:-}" ]] \
  || fail "set SIGNING_IDENTITY to the full Developer ID Application identity"

[[ "$DEVELOPMENT_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] \
  || fail "DEVELOPMENT_TEAM_ID must be a 10-character uppercase Apple Team ID"
[[ "$SIGNING_IDENTITY" == "Developer ID Application: "*\ \("$DEVELOPMENT_TEAM_ID"\) ]] \
  || fail "SIGNING_IDENTITY must be a Developer ID Application identity for DEVELOPMENT_TEAM_ID"

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
    || fail "NOTARY_KEY_PATH must name a readable Team App Store Connect private key"
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
  codesign ditto git hdiutil security shasum spctl xcodebuild xcodegen xcrun
do
  command -v "$required_command" >/dev/null \
    || fail "required command is unavailable: $required_command"
done
[[ -x /usr/bin/plutil && -x /usr/libexec/PlistBuddy ]] \
  || fail "required macOS property-list tools are unavailable"

available_identities="$(security find-identity -v -p codesigning 2>/dev/null)" \
  || fail "security could not enumerate code-signing identities"
[[ "$(grep -Fc "\"$SIGNING_IDENTITY\"" <<< "$available_identities" || true)" -eq 1 ]] \
  || fail "SIGNING_IDENTITY was not found exactly once in available code-signing identities"

version="$(
  sed -n 's/.*MARKETING_VERSION: *"\([^"]*\)".*/\1/p' project.yml | head -1
)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || fail "could not read a semantic MARKETING_VERSION from project.yml"
tag="v$version"

verify_provenance() {
  local untracked_non_build

  git rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || fail "release must run inside a Git worktree"
  git diff --quiet --ignore-submodules -- \
    || fail "tracked worktree changes must be committed before release"
  git diff --cached --quiet --ignore-submodules -- \
    || fail "staged changes must be committed before release"
  untracked_non_build="$(
    git ls-files --others --exclude-standard \
      | grep -Ev '^build(/|$)' || true
  )"
  [[ -z "$untracked_non_build" ]] \
    || fail "untracked non-build files must be committed or removed before release"

  head_commit="$(git rev-parse HEAD)"
  head_tree="$(git rev-parse 'HEAD^{tree}')"
  tag_commit="$(git rev-parse -q --verify "refs/tags/$tag^{commit}" 2>/dev/null)" \
    || fail "required release tag does not exist: $tag"
  [[ "$tag_commit" == "$head_commit" ]] \
    || fail "release tag $tag does not resolve to HEAD"
}

if [[ "$mode" == "release" ]]; then
  verify_provenance
fi

history_result="$(mktemp "${TMPDIR:-/tmp}/talkie-notary-history.XXXXXX")"
if ! xcrun notarytool history \
    "${notary_auth[@]}" \
    --output-format json \
    --no-progress > "$history_result" 2>/dev/null; then
  fail "notarization credential authentication failed"
fi
/usr/bin/plutil -convert json -o /dev/null "$history_result" >/dev/null 2>&1 \
  || fail "notarytool history did not return parseable JSON"
rm -f "$history_result"
history_result=""

if [[ "$mode" == "validate" ]]; then
  echo "Release environment and Apple notarization authentication are valid for: $SIGNING_IDENTITY"
  exit 0
fi

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

final_dir="build/release-$version"
export_options="build/ExportOptions.resolved.plist"
rm -rf "$final_dir"
rm -f "$export_options"
mkdir -p build
staging_root="$(mktemp -d "build/.release-$version.XXXXXX")"

archive="$staging_root/Talkie.xcarchive"
export_dir="$staging_root/export"
app="$export_dir/Talkie.app"
output_dir="$staging_root/output"
work_dir="$staging_root/work"
zip="$output_dir/Talkie-$version.zip"
dmg="$output_dir/Talkie-$version.dmg"
notary_upload_zip="$work_dir/Talkie-$version-notarization-upload.zip"
app_notary_result="$output_dir/notarization-app.json"
dmg_notary_result="$output_dir/notarization-dmg.json"
checksum_file="$output_dir/SHA256SUMS"
metadata_file="$output_dir/release-metadata.txt"
mkdir -p "$output_dir" "$work_dir"

echo "==> Generating and verifying the portable project"
xcodegen generate
scripts/verify-project-config.sh

if grep -Eq 'teamID|__[A-Z0-9_]+__' scripts/ExportOptions.plist; then
  fail "scripts/ExportOptions.plist must not contain a team ID or placeholder"
fi
cp scripts/ExportOptions.plist "$export_options"
/usr/libexec/PlistBuddy -c "Add :teamID string $DEVELOPMENT_TEAM_ID" \
  "$export_options" >/dev/null
[[ "$(/usr/libexec/PlistBuddy -c 'Print :teamID' "$export_options")" == "$DEVELOPMENT_TEAM_ID" ]] \
  || fail "resolved export options do not contain the requested team ID"

echo "==> Running focused release-configuration tests"
xcodebuild test \
  -project Talkie.xcodeproj \
  -scheme Talkie \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData-release \
  -only-testing:TalkieTests/ReleaseConfigurationTests

echo "==> Archiving and exporting with the selected Developer ID identity"
xcodebuild archive \
  -project Talkie.xcodeproj \
  -scheme Talkie \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$archive" \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM_ID" \
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY"
xcodebuild -exportArchive \
  -archivePath "$archive" \
  -exportOptionsPlist "$export_options" \
  -exportPath "$export_dir" \
  DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM_ID" \
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY"

expected_entitlements_json="$(
  /usr/bin/plutil -convert json -o - Talkie/Talkie.entitlements
)"

verify_legal_notices() {
  local candidate_app="$1"
  local notice
  for notice in LICENSE NOTICE THIRD_PARTY_NOTICES.txt; do
    cmp -s "$notice" "$candidate_app/Contents/Resources/$notice" \
      || fail "packaged app legal notice differs from repository source: $notice"
  done
}

verify_production_app() {
  local candidate_app="$1"
  local require_ticket="$2"
  local signature_details entitlements_file actual_entitlements_json

  [[ -d "$candidate_app" ]] || fail "expected Talkie.app is missing"
  verify_legal_notices "$candidate_app"
  codesign --verify --deep --strict --verbose=2 "$candidate_app" \
    || fail "strict code-signature verification failed"

  signature_details="$(mktemp "$staging_root/signature.XXXXXX")"
  if ! LC_ALL=C codesign -dv --verbose=4 "$candidate_app" \
      >/dev/null 2> "$signature_details"; then
    fail "could not inspect the Developer ID signature"
  fi
  [[ "$(grep -Fxc "Authority=$SIGNING_IDENTITY" "$signature_details" || true)" -eq 1 ]] \
    || fail "app signature Authority does not match SIGNING_IDENTITY"
  grep -Fqx "TeamIdentifier=$DEVELOPMENT_TEAM_ID" "$signature_details" \
    || fail "app signature TeamIdentifier does not match DEVELOPMENT_TEAM_ID"
  grep -Eq '^CodeDirectory .*\(runtime([,)])' "$signature_details" \
    || fail "app signature does not enable the hardened runtime"
  grep -Eq '^Timestamp=.+$' "$signature_details" \
    || fail "app signature has no secure timestamp"

  entitlements_file="$(mktemp "$staging_root/entitlements.XXXXXX")"
  if ! codesign -d --entitlements :- --xml "$candidate_app" \
      > "$entitlements_file" 2>/dev/null; then
    fail "could not inspect app entitlements"
  fi
  actual_entitlements_json="$(
    /usr/bin/plutil -convert json -o - "$entitlements_file" 2>/dev/null
  )" || fail "app entitlements are not a valid property list"
  [[ "$actual_entitlements_json" == "$expected_entitlements_json" ]] \
    || fail "app entitlements do not exactly match Talkie/Talkie.entitlements"
  rm -f "$signature_details" "$entitlements_file"

  if [[ "$require_ticket" == "yes" ]]; then
    xcrun stapler validate "$candidate_app" \
      || fail "app does not contain a valid stapled ticket"
    spctl -a -vv --type execute "$candidate_app" \
      || fail "Gatekeeper rejected the app"
  fi
}

verify_production_app "$app" no

submit_for_notarization() {
  local artifact="$1" result_file="$2" artifact_label="$3"
  local notary_exit=0
  xcrun notarytool submit "$artifact" \
    "${notary_auth[@]}" \
    --wait \
    --output-format json \
    --no-progress > "$result_file" 2>/dev/null || notary_exit=$?
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

echo "==> Notarizing and stapling the app payload"
ditto -c -k --keepParent "$app" "$notary_upload_zip"
submit_for_notarization "$notary_upload_zip" "$app_notary_result" "the app upload"
app_notary_status="$submitted_status"
app_notary_request_id="$submitted_request_id"
xcrun stapler staple "$app"
verify_production_app "$app" yes

echo "==> Packaging the stapled app as ZIP and DMG"
ditto -c -k --keepParent "$app" "$zip"
dmg_source="$work_dir/dmg-source"
mkdir -p "$dmg_source"
cp -R "$app" "$dmg_source/"
ln -s /Applications "$dmg_source/Applications"
hdiutil create \
  -volname Talkie \
  -srcfolder "$dmg_source" \
  -format UDZO \
  -ov \
  "$dmg"

echo "==> Notarizing and stapling the exact final DMG"
submit_for_notarization "$dmg" "$dmg_notary_result" "the final DMG"
dmg_notary_status="$submitted_status"
dmg_notary_request_id="$submitted_request_id"
xcrun stapler staple "$dmg"
xcrun stapler validate "$dmg"
spctl -a -vv --type open "$dmg"

echo "==> Verifying the actual packaged app from ZIP"
zip_verification="$work_dir/verification-zip"
mkdir -p "$zip_verification"
ditto -x -k "$zip" "$zip_verification"
verify_production_app "$zip_verification/Talkie.app" yes

echo "==> Verifying the actual packaged app from the read-only DMG"
mounted_path="$work_dir/verification-dmg"
mkdir -p "$mounted_path"
hdiutil attach \
  -readonly \
  -noautoopen \
  -mountpoint "$mounted_path" \
  "$dmg" >/dev/null
verify_production_app "$mounted_path/Talkie.app" yes
hdiutil detach "$mounted_path" >/dev/null
mounted_path=""

echo "==> Generating checksums and release provenance metadata"
(
  cd "$output_dir"
  shasum -a 256 "$(basename "$dmg")" "$(basename "$zip")" \
    | LC_ALL=C sort -k2 > "$(basename "$checksum_file")"
  shasum -a 256 -c "$(basename "$checksum_file")"
)
zip_sha256="$(awk -v name="$(basename "$zip")" '$2 == name { print $1 }' "$checksum_file")"
dmg_sha256="$(awk -v name="$(basename "$dmg")" '$2 == name { print $1 }' "$checksum_file")"
[[ -n "$zip_sha256" && -n "$dmg_sha256" ]] \
  || fail "could not resolve final artifact checksums"
xcode_version="$(xcodebuild -version | paste -sd ';' -)"

{
  echo "tag=$tag"
  echo "version=$version"
  echo "commit=$head_commit"
  echo "tree=$head_tree"
  echo "xcode=$xcode_version"
  echo "macos_deployment_target=$deployment_target"
  echo "hotkey_version=$hotkey_version"
  echo "fluid_audio_version=$fluid_audio_version"
  echo "team_id=$DEVELOPMENT_TEAM_ID"
  echo "signing_identity=$SIGNING_IDENTITY"
  echo "app_notarization_status=$app_notary_status"
  echo "app_notarization_request_id=$app_notary_request_id"
  echo "dmg_notarization_status=$dmg_notary_status"
  echo "dmg_notarization_request_id=$dmg_notary_request_id"
  echo "zip_sha256=$zip_sha256"
  echo "dmg_sha256=$dmg_sha256"
} > "$metadata_file"

mv "$output_dir" "$final_dir"

echo
echo "Supported release promoted atomically:"
echo "  Tag / commit / tree: $tag / $head_commit / $head_tree"
echo "  Signing identity: $SIGNING_IDENTITY"
echo "  App / DMG notarization: $app_notary_status / $dmg_notary_status"
echo "  Artifacts and metadata: $final_dir"
