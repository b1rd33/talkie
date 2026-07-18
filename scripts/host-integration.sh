#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcodegen generate
TALKIE_RUN_HOST_INTEGRATION=1 xcodebuild test \
  -project Talkie.xcodeproj -scheme Talkie \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/talkie-host-integration-derived \
  -only-testing:TalkieHostIntegrationTests
