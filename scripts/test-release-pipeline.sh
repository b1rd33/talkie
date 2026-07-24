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
  local value="$1" expected="$2" message="$3"
  [[ "$value" == *"$expected"* ]] || fail "$message"
}

assert_not_contains() {
  local value="$1" rejected="$2" message="$3"
  [[ "$value" != *"$rejected"* ]] || fail "$message"
}

assert_failure_without_release() {
  local status="$1" root="$2" message="$3"
  [[ "$status" -ne 0 ]] || fail "$message: command unexpectedly succeeded"
  [[ ! -e "$root/build/release-1.0.0" ]] \
    || fail "$message: publishable release directory survived failure"
  [[ ! -e "$root/build/ExportOptions.resolved.plist" ]] \
    || fail "$message: resolved export options survived outside private staging"
  [[ "$(find "$root/build" -maxdepth 1 -name '.release-1.0.0.*' | wc -l | tr -d ' ')" == "0" ]] \
    || fail "$message: private release staging survived failure"
}

make_fixture() {
  local name="$1"
  local root="$fixture_root/$name"
  mkdir -p "$root/scripts" "$root/stubs" "$root/Talkie"
  cp "$repository_root/.gitignore" "$root/.gitignore"
  cp "$repository_root/project.yml" "$root/project.yml"
  cp "$repository_root/LICENSE" "$root/LICENSE"
  cp "$repository_root/NOTICE" "$root/NOTICE"
  cp "$repository_root/THIRD_PARTY_NOTICES.txt" "$root/THIRD_PARTY_NOTICES.txt"
  cp "$repository_root/Talkie/Talkie.entitlements" "$root/Talkie/Talkie.entitlements"
  cp "$repository_root/scripts/ExportOptions.plist" "$root/scripts/ExportOptions.plist"
  cp "$repository_root/scripts/release.sh" "$root/scripts/release.sh"
  cp "$repository_root/scripts/build-release-adhoc.sh" "$root/scripts/build-release-adhoc.sh"
  printf '%s\n' '#!/bin/bash' 'exit 0' > "$root/scripts/verify-project-config.sh"
  chmod +x "$root/scripts/verify-project-config.sh"

  printf '%s\n' \
    '#!/bin/bash' \
    'set -euo pipefail' \
    'command_name="$(basename "$0")"' \
    'state_dir="${STUB_STATE_DIR:?}"' \
    'mkdir -p "$state_dir"' \
    'printf "%s" "$command_name" >> "$COMMAND_LOG"' \
    'printf " <%s>" "$@" >> "$COMMAND_LOG"' \
    'printf "\n" >> "$COMMAND_LOG"' \
    'die() { echo "strict stub rejected $command_name invocation" >&2; exit 97; }' \
    'copy_notices() {' \
    '  local app="$1"' \
    '  mkdir -p "$app/Contents/Resources" "$app/Contents/MacOS"' \
    '  cp LICENSE NOTICE THIRD_PARTY_NOTICES.txt "$app/Contents/Resources/"' \
    '  printf "fixture executable\n" > "$app/Contents/MacOS/Talkie"' \
    '}' \
    'case "$command_name" in' \
    '  security)' \
    '    [[ "$#" -eq 4 && "$1" == "find-identity" && "$2" == "-v" && "$3" == "-p" && "$4" == "codesigning" ]] || die' \
    '    printf "  1) TESTHASH \"%s\"\n" "${SECURITY_IDENTITY:-Developer ID Application: Talkie Test (ABCDE12345)}"' \
    '    ;;' \
    '  xcodegen)' \
    '    [[ "$#" -eq 1 && "$1" == "generate" ]] || die' \
    '    ;;' \
    '  xcodebuild)' \
    '    if [[ "$#" -eq 1 && "$1" == "-version" ]]; then' \
    '      printf "Xcode 99.1\nBuild version 99A1\n"' \
    '      exit 0' \
    '    fi' \
    '    if [[ "${1:-}" == "test" ]]; then exit 0; fi' \
    '    archive_path=""' \
    '    export_path=""' \
    '    previous=""' \
    '    for argument in "$@"; do' \
    '      [[ "$previous" == "-archivePath" ]] && archive_path="$argument"' \
    '      [[ "$previous" == "-exportPath" ]] && export_path="$argument"' \
    '      previous="$argument"' \
    '    done' \
    '    if [[ "${1:-}" == "archive" && -n "$archive_path" ]]; then' \
    '      copy_notices "$archive_path/Products/Applications/Talkie.app"' \
    '    elif [[ "${1:-}" == "-exportArchive" && -n "$archive_path" && -n "$export_path" ]]; then' \
    '      [[ -d "$archive_path/Products/Applications/Talkie.app" ]] || die' \
    '      copy_notices "$export_path/Talkie.app"' \
    '    else' \
    '      die' \
    '    fi' \
    '    ;;' \
    '  codesign)' \
    '    target="${!#}"' \
    '    if [[ "${1:-}" == "--force" ]]; then [[ -d "$target" || -f "$target" ]] || die; exit 0; fi' \
    '    if [[ "${1:-}" == "--verify" ]]; then' \
    '      [[ "$#" -eq 5 && "$2" == "--deep" && "$3" == "--strict" && "$4" == "--verbose=2" ]] || die' \
    '      [[ -d "$target" ]] || die' \
    '      if [[ "${LATE_VERIFY_FAIL:-}" == "packaged" && "$target" == *"verification"* ]]; then exit 96; fi' \
    '      exit 0' \
    '    fi' \
    '    if [[ "${1:-}" == "-dv" && "${2:-}" == "--verbose=4" && "$#" -eq 3 ]]; then' \
    '      [[ -d "$target" ]] || die' \
    '      printf "Executable=%s/Contents/MacOS/Talkie\n" "$target" >&2' \
    '      printf "Identifier=com.archiev.talkie\n" >&2' \
    '      printf "CodeDirectory v=20500 size=100 flags=0x10000(runtime) hashes=1+1 location=embedded\n" >&2' \
    '      printf "Authority=%s\n" "${SIGNATURE_IDENTITY:-Developer ID Application: Talkie Test (ABCDE12345)}" >&2' \
    '      printf "Authority=Developer ID Certification Authority\nAuthority=Apple Root CA\n" >&2' \
    '      printf "Timestamp=25 Jul 2026 at 12:00:00\n" >&2' \
    '      printf "TeamIdentifier=%s\n" "${SIGNATURE_TEAM_ID:-ABCDE12345}" >&2' \
    '      printf "Runtime Version=14.0.0\n" >&2' \
    '      exit 0' \
    '    fi' \
    '    if [[ "${1:-}" == "-d" && "${2:-}" == "--entitlements" && "${3:-}" == ":-" && "${4:-}" == "--xml" && "$#" -eq 5 ]]; then' \
    '      [[ -d "$target" ]] || die' \
    '      if [[ "${BAD_ENTITLEMENTS:-0}" == "1" ]]; then' \
    '        printf "%s\n" "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict><key>com.apple.security.device.audio-input</key><true/><key>com.apple.security.get-task-allow</key><true/></dict></plist>"' \
    '      else' \
    '        printf "%s\n" "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict><key>com.apple.security.device.audio-input</key><true/></dict></plist>"' \
    '      fi' \
    '      exit 0' \
    '    fi' \
    '    die' \
    '    ;;' \
    '  spctl)' \
    '    target="${!#}"' \
    '    [[ -e "$target" ]] || die' \
    '    if [[ "${LATE_VERIFY_FAIL:-}" == "dmg" && "$target" == *.dmg ]]; then exit 96; fi' \
    '    ;;' \
    '  xcrun)' \
    '    if [[ "${1:-}" == "notarytool" && "${2:-}" == "history" ]]; then' \
    '      [[ "$*" == *"--output-format json"* ]] || die' \
    '      [[ "${NOTARY_HISTORY_MODE:-ok}" == "ok" ]] || exit 95' \
    '      printf "%s\n" "{\"history\":[]}"' \
    '      exit 0' \
    '    fi' \
    '    if [[ "${1:-}" == "notarytool" && "${2:-}" == "submit" ]]; then' \
    '      [[ "$*" == *"--wait"* && "$*" == *"--output-format json"* ]] || die' \
    '      count_file="$state_dir/notary-count"' \
    '      count=0; [[ -f "$count_file" ]] && count="$(cat "$count_file")"' \
    '      count=$((count + 1)); printf "%s\n" "$count" > "$count_file"' \
    '      status="${NOTARY_FIRST_STATUS:-Accepted}"' \
    '      [[ "$count" -eq 2 ]] && status="${NOTARY_SECOND_STATUS:-Accepted}"' \
    '      printf "{\"status\":\"%s\",\"id\":\"00000000-0000-0000-0000-00000000000%s\"}\n" "$status" "$count"' \
    '      exit 0' \
    '    fi' \
    '    if [[ "${1:-}" == "stapler" && "${2:-}" == "staple" && "$#" -eq 3 ]]; then' \
    '      target="$3"; [[ -e "$target" ]] || die' \
    '      if [[ -d "$target" ]]; then touch "$target/.stub-stapled"; else touch "$state_dir/dmg-stapled"; fi' \
    '      exit 0' \
    '    fi' \
    '    if [[ "${1:-}" == "stapler" && "${2:-}" == "validate" && "$#" -eq 3 ]]; then' \
    '      target="$3"; [[ -e "$target" ]] || die' \
    '      if [[ -d "$target" ]]; then [[ -f "$target/.stub-stapled" ]] || die; else [[ -f "$state_dir/dmg-stapled" ]] || die; fi' \
    '      exit 0' \
    '    fi' \
    '    die' \
    '    ;;' \
    '  ditto)' \
    '    if [[ "$#" -eq 5 && "$1" == "-c" && "$2" == "-k" && "$3" == "--keepParent" ]]; then' \
    '      source="$4"; destination="$5"; [[ -d "$source" ]] || die' \
    '      if [[ "$destination" != *"notarization-upload"* && "$destination" != *"community-preview"* ]]; then [[ -f "$source/.stub-stapled" ]] || die; fi' \
    '      rm -rf "$state_dir/zip-content"; mkdir -p "$state_dir/zip-content"; cp -R "$source" "$state_dir/zip-content/Talkie.app"' \
    '      mkdir -p "$(dirname "$destination")"; printf "zip fixture\n" > "$destination"; exit 0' \
    '    fi' \
    '    if [[ "$#" -eq 4 && "$1" == "-x" && "$2" == "-k" ]]; then' \
    '      [[ -f "$3" && -d "$state_dir/zip-content/Talkie.app" ]] || die' \
    '      mkdir -p "$4"; cp -R "$state_dir/zip-content/Talkie.app" "$4/Talkie.app"; exit 0' \
    '    fi' \
    '    die' \
    '    ;;' \
    '  hdiutil)' \
    '    if [[ "${1:-}" == "create" ]]; then' \
    '      source=""; previous=""; for argument in "$@"; do [[ "$previous" == "-srcfolder" ]] && source="$argument"; previous="$argument"; done' \
    '      destination="${!#}"; [[ -d "$source/Talkie.app" && -f "$source/Talkie.app/.stub-stapled" ]] || die' \
    '      rm -rf "$state_dir/dmg-content"; mkdir -p "$state_dir/dmg-content"; cp -R "$source/Talkie.app" "$state_dir/dmg-content/Talkie.app"' \
    '      printf "dmg fixture\n" > "$destination"; exit 0' \
    '    fi' \
    '    if [[ "${1:-}" == "attach" ]]; then' \
    '      mountpoint=""; previous=""; for argument in "$@"; do [[ "$previous" == "-mountpoint" ]] && mountpoint="$argument"; previous="$argument"; done' \
    '      image="${!#}"; [[ "$*" == *"-readonly"* && "$*" == *"-noautoopen"* && -f "$image" && -f "$state_dir/dmg-stapled" ]] || die' \
    '      mkdir -p "$mountpoint"; cp -R "$state_dir/dmg-content/Talkie.app" "$mountpoint/Talkie.app"; printf "/dev/disk99\tApple_HFS\t%s\n" "$mountpoint"; exit 0' \
    '    fi' \
    '    if [[ "${1:-}" == "detach" && "$#" -eq 2 ]]; then touch "$state_dir/detached"; exit 0; fi' \
    '    die' \
    '    ;;' \
    '  *) die ;;' \
    'esac' > "$root/stubs/command-stub"
  chmod +x "$root/stubs/command-stub"

  local command_name
  for command_name in codesign ditto hdiutil security spctl xcodebuild xcodegen xcrun; do
    ln -s command-stub "$root/stubs/$command_name"
  done

  git -C "$root" init -q
  git -C "$root" config user.name "Release Fixture"
  git -C "$root" config user.email "release@example.invalid"
  git -C "$root" add .
  git -C "$root" commit -qm "fixture release"
  git -C "$root" tag v1.0.0
  printf '%s\n' "$root"
}

run_release() {
  local root="$1"
  shift
  (
    cd "$root"
    mkdir -p build/stub-state
    PATH="$root/stubs:/usr/bin:/bin:/usr/sbin:/sbin" \
      COMMAND_LOG="$root/build/commands.log" \
      STUB_STATE_DIR="$root/build/stub-state" \
      DEVELOPMENT_TEAM_ID="${DEVELOPMENT_TEAM_ID-}" \
      SIGNING_IDENTITY="${SIGNING_IDENTITY-}" \
      NOTARY_KEYCHAIN_PROFILE="${NOTARY_KEYCHAIN_PROFILE-}" \
      NOTARY_KEY_PATH="${NOTARY_KEY_PATH-}" \
      NOTARY_KEY_ID="${NOTARY_KEY_ID-}" \
      NOTARY_ISSUER_ID="${NOTARY_ISSUER_ID-}" \
      NOTARY_HISTORY_MODE="${NOTARY_HISTORY_MODE-ok}" \
      NOTARY_FIRST_STATUS="${NOTARY_FIRST_STATUS-Accepted}" \
      NOTARY_SECOND_STATUS="${NOTARY_SECOND_STATUS-Accepted}" \
      SECURITY_IDENTITY="${SECURITY_IDENTITY-$identity}" \
      SIGNATURE_IDENTITY="${SIGNATURE_IDENTITY-$identity}" \
      SIGNATURE_TEAM_ID="${SIGNATURE_TEAM_ID-$team_id}" \
      BAD_ENTITLEMENTS="${BAD_ENTITLEMENTS-0}" \
      LATE_VERIFY_FAIL="${LATE_VERIFY_FAIL-}" \
      scripts/release.sh "$@"
  )
}

run_supported_capture() {
  local root="$1"
  shift
  if captured_output="$(
    DEVELOPMENT_TEAM_ID="$team_id" \
      SIGNING_IDENTITY="$identity" \
      NOTARY_KEYCHAIN_PROFILE="$profile_secret" \
      run_release "$root" "$@" 2>&1
  )"; then
    captured_status=0
  else
    captured_status=$?
  fi
}

missing_root="$(make_fixture missing)"
if missing_output="$(run_release "$missing_root" --validate-environment 2>&1)"; then
  missing_status=0
else
  missing_status=$?
fi
[[ "$missing_status" -ne 0 ]] || fail "validation accepted missing environment"
assert_contains "$missing_output" "DEVELOPMENT_TEAM_ID" "missing env failure must name DEVELOPMENT_TEAM_ID"

validation_root="$(make_fixture validation)"
run_supported_capture "$validation_root" --validate-environment
[[ "$captured_status" -eq 0 ]] || fail "profile credential validation should succeed"
assert_not_contains "$captured_output" "$profile_secret" "profile credential leaked to output"
[[ ! -e "$validation_root/build/ExportOptions.resolved.plist" ]] \
  || fail "environment validation created persistent resolved export options"
validation_log="$(cat "$validation_root/build/commands.log")"
assert_contains "$validation_log" "xcrun <notarytool> <history>" "validation must authenticate with notarytool history"

if NOTARY_HISTORY_MODE=reject run_supported_capture "$validation_root" --validate-environment; then :; fi
[[ "$captured_status" -ne 0 ]] || fail "validation accepted rejected profile credentials"
assert_not_contains "$captured_output" "$profile_secret" "rejected profile credential leaked to output"

api_root="$(make_fixture api-validation)"
mkdir -p "$api_root/build"
printf 'fixture private key\n' > "$api_root/build/AuthKey_TESTKEY123.p8"
if api_output="$(
  DEVELOPMENT_TEAM_ID="$team_id" \
    SIGNING_IDENTITY="$identity" \
    NOTARY_KEYCHAIN_PROFILE='' \
    NOTARY_KEY_PATH="$api_root/build/AuthKey_TESTKEY123.p8" \
    NOTARY_KEY_ID='TESTKEY123' \
    NOTARY_ISSUER_ID='12345678-1234-1234-1234-1234567890ab' \
    run_release "$api_root" --validate-environment 2>&1
)"; then
  api_status=0
else
  api_status=$?
fi
[[ "$api_status" -eq 0 ]] || fail "API-key credential validation should succeed"
assert_not_contains "$api_output" "AuthKey_TESTKEY123" "API key path leaked to output"
assert_contains "$(cat "$api_root/build/commands.log")" "xcrun <notarytool> <history>" \
  "API-key validation must authenticate with notarytool history"
if api_rejected_output="$(
  DEVELOPMENT_TEAM_ID="$team_id" \
    SIGNING_IDENTITY="$identity" \
    NOTARY_KEYCHAIN_PROFILE='' \
    NOTARY_KEY_PATH="$api_root/build/AuthKey_TESTKEY123.p8" \
    NOTARY_KEY_ID='TESTKEY123' \
    NOTARY_ISSUER_ID='12345678-1234-1234-1234-1234567890ab' \
    NOTARY_HISTORY_MODE=reject \
    run_release "$api_root" --validate-environment 2>&1
)"; then
  api_rejected_status=0
else
  api_rejected_status=$?
fi
[[ "$api_rejected_status" -ne 0 ]] || fail "validation accepted rejected API credentials"
assert_not_contains "$api_rejected_output" "AuthKey_TESTKEY123" \
  "rejected API key path leaked to output"

mismatch_root="$(make_fixture team-mismatch)"
if mismatch_output="$(
  DEVELOPMENT_TEAM_ID='ZZZZZ99999' \
    SIGNING_IDENTITY="$identity" \
    NOTARY_KEYCHAIN_PROFILE='test-profile' \
    run_release "$mismatch_root" --validate-environment 2>&1
)"; then
  mismatch_status=0
else
  mismatch_status=$?
fi
[[ "$mismatch_status" -ne 0 ]] || fail "identity/team mismatch passed preflight"

for provenance_case in dirty untracked untagged tag-mismatch; do
  provenance_root="$(make_fixture "$provenance_case")"
  case "$provenance_case" in
    dirty) printf '\n# dirty\n' >> "$provenance_root/project.yml" ;;
    untracked) printf 'unexpected\n' > "$provenance_root/untracked.txt" ;;
    untagged) git -C "$provenance_root" tag -d v1.0.0 >/dev/null ;;
    tag-mismatch)
      printf 'second\n' > "$provenance_root/provenance.txt"
      git -C "$provenance_root" add provenance.txt
      git -C "$provenance_root" commit -qm "move head past tag"
      ;;
  esac
  run_supported_capture "$provenance_root"
  assert_failure_without_release "$captured_status" "$provenance_root" "$provenance_case provenance"
done

accepted_root="$(make_fixture accepted)"
run_supported_capture "$accepted_root"
[[ "$captured_status" -eq 0 ]] || fail "strict supported release fixture failed: $captured_output"
assert_not_contains "$captured_output" "$profile_secret" "supported release leaked profile credential"
accepted_log="$(cat "$accepted_root/build/commands.log")"
[[ "$(grep -c '^xcrun <notarytool> <submit>' "$accepted_root/build/commands.log")" == "2" ]] \
  || fail "supported release did not perform exactly two notarizations"
for required_call in \
  'xcrun <notarytool> <history>' \
  'codesign <-dv> <--verbose=4>' \
  'codesign <-d> <--entitlements> <:-> <--xml>' \
  'ditto <-x> <-k>' \
  'hdiutil <attach> <-readonly> <-noautoopen>' \
  'hdiutil <detach>'
do
  assert_contains "$accepted_log" "$required_call" "missing strict verification call: $required_call"
done

release_dir="$accepted_root/build/release-1.0.0"
for artifact in Talkie-1.0.0.zip Talkie-1.0.0.dmg SHA256SUMS release-metadata.txt notarization-app.json notarization-dmg.json; do
  [[ -f "$release_dir/$artifact" ]] || fail "final release missing $artifact"
done
[[ "$(find "$accepted_root/build" -maxdepth 1 -name '.release-1.0.0.*' | wc -l | tr -d ' ')" == "0" ]] \
  || fail "private release staging survived success"
[[ ! -e "$accepted_root/build/ExportOptions.resolved.plist" ]] \
  || fail "resolved export options survived outside private staging after success"
for metadata_value in \
  "tag=v1.0.0" \
  "commit=$(git -C "$accepted_root" rev-parse HEAD)" \
  "tree=$(git -C "$accepted_root" rev-parse 'HEAD^{tree}')" \
  "team_id=$team_id" \
  "signing_identity=$identity" \
  "hotkey_version=0.2.1" \
  "fluid_audio_version=0.15.5"
do
  grep -Fqx "$metadata_value" "$release_dir/release-metadata.txt" \
    || fail "release metadata missing $metadata_value"
done
(cd "$release_dir" && shasum -a 256 -c SHA256SUMS >/dev/null) \
  || fail "supported release checksums did not verify"

for failure_case in \
  second-notary late-verifier bad-entitlements signature-team signature-authority
do
  failure_root="$(make_fixture "$failure_case")"
  case "$failure_case" in
    second-notary) NOTARY_SECOND_STATUS=Invalid run_supported_capture "$failure_root" ;;
    late-verifier) LATE_VERIFY_FAIL=dmg run_supported_capture "$failure_root" ;;
    bad-entitlements) BAD_ENTITLEMENTS=1 run_supported_capture "$failure_root" ;;
    signature-team) SIGNATURE_TEAM_ID=ZZZZZ99999 run_supported_capture "$failure_root" ;;
    signature-authority)
      SIGNATURE_IDENTITY='Developer ID Application: Other Signer (ABCDE12345)' \
        run_supported_capture "$failure_root"
      ;;
  esac
  assert_failure_without_release "$captured_status" "$failure_root" "$failure_case"
done

preview_root="$(make_fixture preview)"
if preview_output="$(
  cd "$preview_root"
  mkdir -p build/stub-state
  PATH="$preview_root/stubs:/usr/bin:/bin:/usr/sbin:/sbin" \
    COMMAND_LOG="$preview_root/build/commands.log" \
    STUB_STATE_DIR="$preview_root/build/stub-state" \
    scripts/build-release-adhoc.sh 2>&1
)"; then
  preview_status=0
else
  preview_status=$?
fi
[[ "$preview_status" -eq 0 ]] || fail "strict community-preview fixture failed: $preview_output"
assert_contains "$preview_output" "community preview" "preview output lacks community-preview label"
preview_log="$(cat "$preview_root/build/commands.log")"
assert_not_contains "$preview_log" "notarytool" "community preview invoked notarytool"
assert_not_contains "$preview_log" "spctl" "community preview invoked spctl"
assert_contains "$preview_log" "ditto <-x> <-k>" \
  "community preview did not extract its packaged ZIP for verification"
assert_contains "$preview_log" "community-preview-verification" \
  "community preview did not verify the extracted app"
preview_dir="$preview_root/build/community-preview-1.0.0"
(cd "$preview_dir" && shasum -a 256 -c SHA256SUMS >/dev/null) \
  || fail "community-preview checksum did not verify"
for notice in LICENSE NOTICE THIRD_PARTY_NOTICES.txt; do
  cmp -s "$preview_root/$notice" "$preview_root/build/stub-state/zip-content/Talkie.app/Contents/Resources/$notice" \
    || fail "packaged community preview changed legal notice $notice"
done

if ((${#failures[@]})); then
  printf 'release-pipeline test failed (%d issue(s))\n' "${#failures[@]}" >&2
  printf ' - %s\n' "${failures[@]}" >&2
  exit 1
fi

echo "Release-pipeline tests passed."
