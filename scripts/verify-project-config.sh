#!/bin/bash
set -euo pipefail

project_file="${1:-project.yml}"

require_line() {
  local pattern="$1"
  local message="$2"
  if ! grep -Eq "$pattern" "$project_file"; then
    echo "error: $message" >&2
    exit 1
  fi
}

if grep -Eq '^[[:space:]]+from:' "$project_file"; then
  echo "error: package dependencies must use exactVersion, not a version range" >&2
  exit 1
fi

require_line 'exactVersion:[[:space:]]+0\.2\.1' 'HotKey must be pinned to 0.2.1'
require_line 'exactVersion:[[:space:]]+0\.15\.5' 'FluidAudio must be pinned to 0.15.5'
require_line 'ENABLE_HARDENED_RUNTIME:[[:space:]]+YES' 'hardened runtime must be enabled by default'
require_line 'CODE_SIGN_ENTITLEMENTS:[[:space:]]+Talkie/Talkie\.entitlements' 'Talkie entitlements must be configured'
require_line 'CODE_SIGN_IDENTITY:[[:space:]]+"Developer ID Application"' 'Release must use Developer ID signing'
require_line 'ReleaseAdhoc:' 'the explicitly separate ad-hoc release configuration is required'

echo "Project configuration checks passed."
