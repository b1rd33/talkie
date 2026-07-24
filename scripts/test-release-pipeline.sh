#!/bin/bash
set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
fixture_root="$(mktemp -d "${TMPDIR:-/tmp}/talkie-release-pipeline.XXXXXX")"
trap 'rm -rf "$fixture_root"' EXIT

failures=()
identity='Developer ID Application: Talkie Test (ABCDE12345)'
team_id='ABCDE12345'
profile_secret='profile-value-that-must-not-be-printed'

fail() {
  failures+=("$1")
}

assert_contains() {
  local value="$1"
  local expected="$2"
  local message="$3"
  [[ "$value" == *"$expected"* ]] || fail "$message"
}

assert_not_contains() {
  local value="$1"
  local rejected="$2"
  local message="$3"
  [[ "$value" != *"$rejected"* ]] || fail "$message"
}

make_fixture() {
  local name="$1"
  local root="$fixture_root/$name"
  mkdir -p "$root/scripts" "$root/stubs"
  cp "$repository_root/project.yml" "$root/project.yml"
  cp "$repository_root/LICENSE" "$root/LICENSE"
  cp "$repository_root/NOTICE" "$root/NOTICE"
  cp "$repository_root/THIRD_PARTY_NOTICES.txt" "$root/THIRD_PARTY_NOTICES.txt"
  cp "$repository_root/scripts/ExportOptions.plist" "$root/scripts/ExportOptions.plist"
  cp "$repository_root/scripts/release.sh" "$root/scripts/release.sh"
  cp "$repository_root/scripts/build-release-adhoc.sh" "$root/scripts/build-release-adhoc.sh"
  printf '%s\n' '#!/bin/bash' 'exit 0' > "$root/scripts/verify-project-config.sh"
  chmod +x "$root/scripts/verify-project-config.sh"

  printf '%s\n' '#!/bin/bash' \
    'set -euo pipefail' \
    'command_name="$(basename "$0")"' \
    'printf "%s" "$command_name" >> "$COMMAND_LOG"' \
    'printf " <%s>" "$@" >> "$COMMAND_LOG"' \
    'printf "\n" >> "$COMMAND_LOG"' \
    'case "$command_name" in' \
    '  security)' \
    '    printf "  1) TESTHASH \"Developer ID Application: Talkie Test (ABCDE12345)\"\n"' \
    '    ;;' \
    '  xcodebuild)' \
    '    if [[ "${1:-}" == "-version" ]]; then' \
    '      printf "Xcode 99.1\nBuild version 99A1\n"' \
    '      exit 0' \
    '    fi' \
    '    archive_path=""' \
    '    export_path=""' \
    '    previous=""' \
    '    for argument in "$@"; do' \
    '      [[ "$previous" == "-archivePath" ]] && archive_path="$argument"' \
    '      [[ "$previous" == "-exportPath" ]] && export_path="$argument"' \
    '      previous="$argument"' \
    '    done' \
    '    if [[ "${1:-}" == "archive" && -n "$archive_path" ]]; then' \
    '      mkdir -p "$archive_path/Products/Applications/Talkie.app/Contents/Resources"' \
    '      cp LICENSE NOTICE THIRD_PARTY_NOTICES.txt "$archive_path/Products/Applications/Talkie.app/Contents/Resources/"' \
    '    fi' \
    '    if [[ -n "$export_path" ]]; then' \
    '      mkdir -p "$export_path/Talkie.app/Contents/Resources"' \
    '      cp LICENSE NOTICE THIRD_PARTY_NOTICES.txt "$export_path/Talkie.app/Contents/Resources/"' \
    '    fi' \
    '    ;;' \
    '  xcrun)' \
    '    if [[ "${1:-}" == "notarytool" && "${2:-}" == "submit" ]]; then' \
    '      if [[ -n "${NOTARY_RESPONSE:-}" ]]; then' \
    '        printf "%s\n" "$NOTARY_RESPONSE"' \
    '      else' \
    '        printf "%s\n" "{\"status\":\"Accepted\",\"id\":\"00000000-0000-0000-0000-000000000000\"}"' \
    '      fi' \
    '      exit "${NOTARY_EXIT:-0}"' \
    '    fi' \
    '    ;;' \
    '  ditto)' \
    '    destination="${!#}"' \
    '    mkdir -p "$(dirname "$destination")"' \
    '    printf "zip fixture\n" > "$destination"' \
    '    ;;' \
    '  hdiutil)' \
    '    destination="${!#}"' \
    '    mkdir -p "$(dirname "$destination")"' \
    '    printf "dmg fixture\n" > "$destination"' \
    '    ;;' \
    '  git)' \
    '    printf "0123456789abcdef0123456789abcdef01234567\n"' \
    '    ;;' \
    'esac' > "$root/stubs/command-stub"
  chmod +x "$root/stubs/command-stub"

  local command_name
  for command_name in \
    codesign ditto git hdiutil security spctl xcodebuild xcodegen xcrun
  do
    ln -s command-stub "$root/stubs/$command_name"
  done

  printf '%s\n' "$root"
}

run_release() {
  local root="$1"
  shift
  (
    cd "$root"
    PATH="$root/stubs:/usr/bin:/bin:/usr/sbin:/sbin" \
      COMMAND_LOG="$root/commands.log" \
      DEVELOPMENT_TEAM_ID="${DEVELOPMENT_TEAM_ID-}" \
      SIGNING_IDENTITY="${SIGNING_IDENTITY-}" \
      NOTARY_KEYCHAIN_PROFILE="${NOTARY_KEYCHAIN_PROFILE-}" \
      NOTARY_KEY_PATH="${NOTARY_KEY_PATH-}" \
      NOTARY_KEY_ID="${NOTARY_KEY_ID-}" \
      NOTARY_ISSUER_ID="${NOTARY_ISSUER_ID-}" \
      NOTARY_RESPONSE="${NOTARY_RESPONSE-}" \
      NOTARY_EXIT="${NOTARY_EXIT-}" \
      scripts/release.sh "$@"
  )
}

missing_root="$(make_fixture missing-environment)"
missing_output="$(run_release "$missing_root" --validate-environment 2>&1 || true)"
if run_release "$missing_root" --validate-environment >/dev/null 2>&1; then
  fail "release validation accepted missing signing and notarization environment"
fi
assert_contains "$missing_output" "DEVELOPMENT_TEAM_ID" \
  "missing-environment failure must name DEVELOPMENT_TEAM_ID"
assert_not_contains "$missing_output" "DEVELOPMENT_TEAM=" \
  "release must not advertise the retired DEVELOPMENT_TEAM interface"

if grep -Eq 'teamID|__[A-Z0-9_]+__|[A-Z0-9]{10}' \
    "$repository_root/scripts/ExportOptions.plist"; then
  fail "tracked ExportOptions.plist contains a team ID or placeholder"
fi

accepted_root="$(make_fixture accepted)"
mkdir -p "$accepted_root/build/release-1.0.0"
printf 'stale\n' > "$accepted_root/build/release-1.0.0/Talkie-stale.zip"
accepted_output="$(
  DEVELOPMENT_TEAM_ID="$team_id" \
    SIGNING_IDENTITY="$identity" \
    NOTARY_KEYCHAIN_PROFILE="$profile_secret" \
    NOTARY_RESPONSE='{"status":"Accepted","id":"11111111-2222-3333-4444-555555555555"}' \
    run_release "$accepted_root" 2>&1 || true
)"
if ! DEVELOPMENT_TEAM_ID="$team_id" \
    SIGNING_IDENTITY="$identity" \
    NOTARY_KEYCHAIN_PROFILE="$profile_secret" \
    run_release "$accepted_root" --validate-environment >/dev/null 2>&1; then
  fail "stubbed release environment validation did not succeed"
fi
assert_not_contains "$accepted_output" "$profile_secret" \
  "release output leaked the notarization profile value"

resolved_plist="$accepted_root/build/ExportOptions.resolved.plist"
if [[ ! -f "$resolved_plist" ]]; then
  fail "release did not generate build/ExportOptions.resolved.plist"
elif [[ "$(/usr/libexec/PlistBuddy -c 'Print :teamID' "$resolved_plist" 2>/dev/null || true)" != "$team_id" ]]; then
  fail "resolved export options did not contain the validated team ID"
fi

accepted_log="$(cat "$accepted_root/commands.log" 2>/dev/null || true)"
[[ "$(grep -c '^xcrun <notarytool> <submit>' "$accepted_root/commands.log" 2>/dev/null || true)" == "2" ]] \
  || fail "supported release must notarize the app upload and final DMG separately"
assert_contains "$accepted_log" \
  'xcrun <notarytool> <submit> <build/release-1.0.0/Talkie-1.0.0-notarization-upload.zip>' \
  "first notarization must submit the app upload ZIP"
assert_contains "$accepted_log" \
  'xcrun <notarytool> <submit> <build/release-1.0.0/Talkie-1.0.0.dmg>' \
  "second notarization must submit the exact final DMG"
for expected_call in \
  'codesign <--verify> <--deep> <--strict> <--verbose=2>' \
  'spctl <-a> <-vv>' \
  'xcrun <stapler> <staple>' \
  'xcrun <stapler> <validate>'
do
  assert_contains "$accepted_log" "$expected_call" \
    "supported release did not invoke required verifier: $expected_call"
done
first_notary_line="$(
  grep -n -m1 '^xcrun <notarytool> <submit>' "$accepted_root/commands.log" \
    | cut -d: -f1 || true
)"
app_staple_line="$(
  grep -n -m1 '^xcrun <stapler> <staple> .*Talkie.app' "$accepted_root/commands.log" \
    | cut -d: -f1 || true
)"
dmg_build_line="$(
  grep -n -m1 '^hdiutil <create>' "$accepted_root/commands.log" \
    | cut -d: -f1 || true
)"
second_notary_line="$(
  grep -n '^xcrun <notarytool> <submit>' "$accepted_root/commands.log" \
    | tail -1 | cut -d: -f1 || true
)"
dmg_staple_line="$(
  grep -n '^xcrun <stapler> <staple> .*Talkie.*dmg' "$accepted_root/commands.log" \
    | tail -1 | cut -d: -f1 || true
)"
if [[ -z "$first_notary_line" || -z "$app_staple_line" ||
      -z "$dmg_build_line" || -z "$second_notary_line" ||
      -z "$dmg_staple_line" ||
      "$first_notary_line" -ge "$app_staple_line" ||
      "$app_staple_line" -ge "$dmg_build_line" ||
      "$dmg_build_line" -ge "$second_notary_line" ||
      "$second_notary_line" -ge "$dmg_staple_line" ]]; then
  fail "notarization/stapling order must be app upload, app staple, DMG build, DMG submit, DMG staple"
fi
assert_contains "$accepted_output" "Accepted" \
  "supported release did not report Accepted notarization"
assert_contains "$accepted_output" "11111111-2222-3333-4444-555555555555" \
  "supported release did not report the non-sensitive notarization request ID"

release_dir="$accepted_root/build/release-1.0.0"
checksum_file="$release_dir/SHA256SUMS"
if [[ ! -f "$checksum_file" ]]; then
  fail "supported release did not generate SHA256SUMS"
else
  [[ "$(wc -l < "$checksum_file" | tr -d ' ')" == "2" ]] \
    || fail "supported release checksums must contain exactly ZIP and DMG"
  grep -Fq "Talkie-stale.zip" "$checksum_file" \
    && fail "supported release checksums included a stale artifact"
fi
[[ ! -e "$release_dir/Talkie-stale.zip" ]] \
  || fail "supported release output directory retained a stale artifact"

rejected_root="$(make_fixture rejected)"
rejected_output="$(
  DEVELOPMENT_TEAM_ID="$team_id" \
    SIGNING_IDENTITY="$identity" \
    NOTARY_KEYCHAIN_PROFILE='test-profile' \
    NOTARY_RESPONSE='{"status":"Invalid","id":"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"}' \
    run_release "$rejected_root" 2>&1 || true
)"
if DEVELOPMENT_TEAM_ID="$team_id" \
    SIGNING_IDENTITY="$identity" \
    NOTARY_KEYCHAIN_PROFILE='test-profile' \
    NOTARY_RESPONSE='{"status":"Invalid","id":"aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"}' \
    run_release "$rejected_root" >/dev/null 2>&1; then
  fail "release accepted an Invalid notarization response"
fi
assert_contains "$rejected_output" "Invalid" \
  "rejected notarization failure must name the returned status"

preview_root="$(make_fixture community-preview)"
preview_output="$(
  (
    cd "$preview_root"
    PATH="$preview_root/stubs:/usr/bin:/bin:/usr/sbin:/sbin" \
      COMMAND_LOG="$preview_root/commands.log" \
      scripts/build-release-adhoc.sh
  ) 2>&1 || true
)"
preview_log="$(cat "$preview_root/commands.log" 2>/dev/null || true)"
assert_contains "$preview_output" "community preview" \
  "ad-hoc build output must identify the artifact as a community preview"
assert_contains "$preview_output" "NOT notarized" \
  "ad-hoc build output must explicitly say it is not notarized"
assert_not_contains "$preview_log" "notarytool" \
  "ad-hoc build must never invoke notarytool"
assert_not_contains "$preview_log" "spctl" \
  "ad-hoc build must never invoke or claim a Gatekeeper assessment"
preview_dir="$preview_root/build/community-preview-1.0.0"
preview_zip="$preview_dir/Talkie-1.0.0-community-preview-adhoc.zip"
[[ -f "$preview_zip" ]] || fail "community preview uses the wrong artifact name"
[[ -f "$preview_dir/SHA256SUMS" ]] \
  || fail "community preview did not generate SHA256SUMS"
for notice in LICENSE NOTICE THIRD_PARTY_NOTICES.txt; do
  [[ -f "$preview_root/build/export-community-preview/Talkie.app/Contents/Resources/$notice" ]] \
    || fail "community preview app is missing legal notice $notice"
done

if ((${#failures[@]})); then
  printf 'release-pipeline test failed (%d issue(s))\n' "${#failures[@]}" >&2
  printf ' - %s\n' "${failures[@]}" >&2
  exit 1
fi

echo "Release-pipeline tests passed."
