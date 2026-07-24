#!/bin/bash
set -euo pipefail

project_file="${1:-project.yml}"

require_file() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    echo "error: required public repository file is missing" >&2
    exit 1
  fi
}

require_line() {
  local pattern="$1"
  local message="$2"
  if ! grep -Eq "$pattern" "$project_file"; then
    echo "error: $message" >&2
    exit 1
  fi
}

for required_document in LICENSE PRIVACY.md SECURITY.md; do
  require_file "$required_document"
done

scripts/scan-sensitive-content.sh
scripts/verify-dependency-mirror.sh "$project_file" Package.swift

if grep -Eq '^[[:space:]]+from:' "$project_file"; then
  echo "error: package dependencies must use exactVersion, not a version range" >&2
  exit 1
fi

require_line 'exactVersion:[[:space:]]+0\.2\.1' 'HotKey must be pinned to 0.2.1'
require_line 'exactVersion:[[:space:]]+0\.15\.5' 'FluidAudio must be pinned to 0.15.5'
require_line 'path:[[:space:]]+LICENSE' 'the Apache license must be bundled as an app resource'
require_line 'path:[[:space:]]+NOTICE' 'the Apache notice must be bundled as an app resource'
require_line 'path:[[:space:]]+THIRD_PARTY_NOTICES\.txt' 'third-party notices must be bundled as an app resource'
require_line 'ReleaseAdhoc:' 'the explicitly separate ad-hoc release configuration is required'

if [[ ! -f Talkie.xcodeproj/project.pbxproj ]]; then
  echo "error: generated Talkie.xcodeproj is missing; run 'xcodegen generate' before verification" >&2
  exit 1
fi

verification_dir="$(mktemp -d "${TMPDIR:-/tmp}/talkie-project-verification.XXXXXX")"
trap 'rm -rf "$verification_dir"' EXIT

capture_build_settings() {
  local configuration="$1"
  local output="$verification_dir/${configuration}.json"
  local log="$verification_dir/${configuration}.log"
  if ! xcodebuild \
      -project Talkie.xcodeproj \
      -target Talkie \
      -configuration "$configuration" \
      -showBuildSettings \
      -json >"$output" 2>"$log"; then
    echo "error: could not inspect generated $configuration build settings" >&2
    cat "$log" >&2
    exit 1
  fi
}

setting_value() {
  local configuration="$1"
  local key="$2"
  ruby -rjson -e '
    target = JSON.parse(File.read(ARGV.fetch(0))).find { |entry| entry["target"] == "Talkie" }
    abort "Talkie target missing from generated build settings" unless target
    print target.fetch("buildSettings").fetch(ARGV.fetch(1), "")
  ' "$verification_dir/${configuration}.json" "$key"
}

assert_setting() {
  local configuration="$1"
  local key="$2"
  local expected="$3"
  local actual
  actual="$(setting_value "$configuration" "$key")"
  if [[ "$actual" != "$expected" ]]; then
    echo "error: generated $configuration $key must be '$expected' (got '$actual')" >&2
    exit 1
  fi
}

assert_entitlement() {
  local file="$1"
  local key="$2"
  local expected="$3"
  local escaped_key="${key//./\\.}"
  local actual
  if ! actual="$(plutil -extract "$escaped_key" raw "$file" 2>/dev/null)"; then
    echo "error: $file must define entitlement $key" >&2
    exit 1
  fi
  if [[ "$actual" != "$expected" ]]; then
    echo "error: $file entitlement $key must be $expected" >&2
    exit 1
  fi
}

reject_entitlement() {
  local file="$1"
  local key="$2"
  local escaped_key="${key//./\\.}"
  if plutil -extract "$escaped_key" raw "$file" >/dev/null 2>&1; then
    echo "error: $file must not define entitlement $key" >&2
    exit 1
  fi
}

capture_build_settings Debug
capture_build_settings Release

assert_setting Debug ENABLE_HARDENED_RUNTIME YES
assert_setting Debug CODE_SIGN_STYLE Manual
assert_setting Debug CODE_SIGN_IDENTITY -
assert_setting Debug OTHER_CODE_SIGN_FLAGS --options=runtime
assert_setting Debug ENABLE_DEBUG_DYLIB NO
assert_setting Debug CODE_SIGN_ENTITLEMENTS Talkie/TalkieDebug.entitlements
assert_setting Debug DEVELOPMENT_TEAM ""

assert_setting Release ENABLE_HARDENED_RUNTIME YES
assert_setting Release CODE_SIGN_STYLE Manual
assert_setting Release CODE_SIGN_IDENTITY "Developer ID Application"
assert_setting Release CODE_SIGN_ENTITLEMENTS Talkie/Talkie.entitlements
assert_setting Release DEVELOPMENT_TEAM ""

require_file Talkie/Talkie.entitlements
require_file Talkie/TalkieDebug.entitlements
assert_entitlement Talkie/TalkieDebug.entitlements com.apple.security.device.audio-input true
assert_entitlement Talkie/TalkieDebug.entitlements com.apple.security.cs.disable-library-validation true
assert_entitlement Talkie/Talkie.entitlements com.apple.security.device.audio-input true
reject_entitlement Talkie/Talkie.entitlements com.apple.security.cs.disable-library-validation
reject_entitlement Talkie/Talkie.entitlements com.apple.security.app-sandbox

hotkey_notice_sha="$(shasum -a 256 THIRD_PARTY_NOTICES.txt | awk '{print $1}')"
if [[ "$hotkey_notice_sha" != "c3aa498d7259097eb52a1f15b7ac82a7159fadf566040de78276267c7664d274" ]]; then
  echo "error: THIRD_PARTY_NOTICES.txt must match HotKey 0.2.1's complete MIT license" >&2
  exit 1
fi

echo "Project configuration checks passed."
