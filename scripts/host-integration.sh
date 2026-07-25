#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

validate_host_result() {
  local summary_path="$1"
  local total passed failed skipped result
  total="$(/usr/bin/plutil -extract totalTestCount raw -o - "$summary_path")"
  passed="$(/usr/bin/plutil -extract passedTests raw -o - "$summary_path")"
  failed="$(/usr/bin/plutil -extract failedTests raw -o - "$summary_path")"
  skipped="$(/usr/bin/plutil -extract skippedTests raw -o - "$summary_path")"
  result="$(/usr/bin/plutil -extract result raw -o - "$summary_path")"

  if [[ "$total" != "3" || "$passed" != "3" || "$failed" != "0" ||
        "$skipped" != "0" || "$result" != "Passed" ]]; then
    echo "error: host integration result was not exactly 3 passed, 0 failed, 0 skipped" >&2
    echo "result=$result total=$total passed=$passed failed=$failed skipped=$skipped" >&2
    return 1
  fi
}

if [[ "${1:-}" == "--validate-summary" ]]; then
  if [[ "$#" != "2" ]]; then
    echo "usage: $0 --validate-summary <summary.json>" >&2
    exit 2
  fi
  validate_host_result "$2"
  exit
fi

xcodegen generate
xcodebuild build-for-testing \
  -project Talkie.xcodeproj -scheme TalkieHostIntegration \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/talkie-host-integration-derived \
  -only-testing:TalkieHostIntegrationTests

host_integration_marker="$(mktemp "${TMPDIR:-/tmp}/talkie-host-integration.XXXXXX")"
host_integration_token="$(uuidgen)"
chmod 600 "$host_integration_marker"
printf '%s\n' "$host_integration_token" > "$host_integration_marker"
export TALKIE_HOST_INTEGRATION_TOKEN="$host_integration_token"
export TALKIE_HOST_INTEGRATION_MARKER="$host_integration_marker"
trap 'rm -f -- "$host_integration_marker"' EXIT

host_integration_result="${TMPDIR:-/tmp}/talkie-host-integration-${host_integration_token}.xcresult"
host_integration_summary="${host_integration_result}.summary.json"
xcodebuild test-without-building \
  -project Talkie.xcodeproj -scheme TalkieHostIntegration \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/talkie-host-integration-derived \
  -resultBundlePath "$host_integration_result" \
  -only-testing:TalkieHostIntegrationTests

xcrun xcresulttool get test-results summary \
  --path "$host_integration_result" > "$host_integration_summary"
validate_host_result "$host_integration_summary"

echo "Host integration passed: 3 tests, 0 failures, 0 skips"
echo "Result bundle: $host_integration_result"
