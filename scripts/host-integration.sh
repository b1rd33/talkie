#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
host_integration_marker="/tmp/talkie-host-integration.enabled"
touch "$host_integration_marker"
trap 'rm -f "$host_integration_marker"' EXIT
xcodegen generate
TALKIE_RUN_HOST_INTEGRATION=1 xcodebuild test \
  -project Talkie.xcodeproj -scheme Talkie \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/talkie-host-integration-derived \
  -only-testing:TalkieHostIntegrationTests
