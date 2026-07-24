#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

host_integration_marker="$(mktemp "${TMPDIR:-/tmp}/talkie-host-integration.XXXXXX")"
host_integration_token="$(uuidgen)"
chmod 600 "$host_integration_marker"
printf '%s\n' "$host_integration_token" > "$host_integration_marker"
export TALKIE_HOST_INTEGRATION_TOKEN="$host_integration_token"
export TALKIE_HOST_INTEGRATION_MARKER="$host_integration_marker"
trap 'rm -f -- "$host_integration_marker"' EXIT

xcodegen generate
xcodebuild test \
  -project Talkie.xcodeproj -scheme TalkieHostIntegration \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/talkie-host-integration-derived \
  -only-testing:TalkieHostIntegrationTests
