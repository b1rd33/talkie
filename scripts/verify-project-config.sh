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

if grep -Eq '^[[:space:]]+from:' "$project_file"; then
  echo "error: package dependencies must use exactVersion, not a version range" >&2
  exit 1
fi

require_line 'exactVersion:[[:space:]]+0\.2\.1' 'HotKey must be pinned to 0.2.1'
require_line 'exactVersion:[[:space:]]+0\.15\.5' 'FluidAudio must be pinned to 0.15.5'
require_line 'path:[[:space:]]+LICENSE' 'the Apache license must be bundled as an app resource'
require_line 'path:[[:space:]]+NOTICE' 'the Apache notice must be bundled as an app resource'
require_line 'path:[[:space:]]+THIRD_PARTY_NOTICES\.txt' 'third-party notices must be bundled as an app resource'
require_line 'ENABLE_HARDENED_RUNTIME:[[:space:]]+YES' 'hardened runtime must be enabled by default'
require_line 'CODE_SIGN_ENTITLEMENTS:[[:space:]]+Talkie/Talkie\.entitlements' 'Talkie entitlements must be configured'
require_line 'CODE_SIGN_IDENTITY:[[:space:]]+"Developer ID Application"' 'Release must use Developer ID signing'
require_line 'ReleaseAdhoc:' 'the explicitly separate ad-hoc release configuration is required'

hotkey_notice_sha="$(shasum -a 256 THIRD_PARTY_NOTICES.txt | awk '{print $1}')"
if [[ "$hotkey_notice_sha" != "c3aa498d7259097eb52a1f15b7ac82a7159fadf566040de78276267c7664d274" ]]; then
  echo "error: THIRD_PARTY_NOTICES.txt must match HotKey 0.2.1's complete MIT license" >&2
  exit 1
fi

echo "Project configuration checks passed."
