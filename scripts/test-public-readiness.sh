#!/bin/bash
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

failures=()

expect_file() {
  local path="$1"
  [[ -f "$path" ]] || failures+=("missing $path")
}

expect_line() {
  local path="$1"
  local line="$2"
  if [[ ! -f "$path" ]] || ! grep -Fqx -- "$line" "$path"; then
    failures+=("$path: missing exact line $line")
  fi
}

expect_pattern() {
  local path="$1"
  local pattern="$2"
  local message="$3"
  if [[ ! -f "$path" ]] || ! grep -Eq -- "$pattern" "$path"; then
    failures+=("$path: $message")
  fi
}

reject_pattern() {
  local path="$1"
  local pattern="$2"
  local message="$3"
  if [[ -f "$path" ]] && grep -Eq -- "$pattern" "$path"; then
    failures+=("$path: $message")
  fi
}

for entry in \
  ".superpowers/" ".worktrees/" "AGENTS.md" ".impeccable.md" \
  ".env" ".env.*" "*.p8" "*.p12" "*.pem" "*.key" "*.cer" \
  "*.mobileprovision" "ExportOptions.local.plist" \
  "build/" "DerivedData/" "*.xcresult"
do
  expect_line .gitignore "$entry"
done

ci=".github/workflows/ci.yml"
expect_file "$ci"
expect_pattern "$ci" '^permissions:$' "missing top-level permissions"
expect_pattern "$ci" '^[[:space:]]+contents:[[:space:]]+read$' "contents permission must be read-only"
expect_pattern "$ci" '^[[:space:]]+timeout-minutes:[[:space:]]+45$' "logic-and-ui timeout must be 45 minutes"
expect_pattern "$ci" 'xcodegen generate' "project must be generated with XcodeGen"
expect_pattern "$ci" 'scan-sensitive-content\.sh[[:space:]]+--tracked-only' "tracked-file sensitive-content scan missing"
expect_pattern "$ci" 'if:[[:space:]]+failure\(\)' "test artifacts must only upload on failure"
expect_pattern "$ci" 'retention-days:[[:space:]]+[1-3]$' "test artifacts need short retention"
reject_pattern "$ci" 'OPENAI_API_KEY|OPENROUTER_API_KEY|api\.openai\.com|openrouter\.ai' "CI must not use provider credentials or live endpoints"

while IFS= read -r action; do
  if [[ ! "$action" =~ ^[[:space:]]*uses:[[:space:]]+[^@[:space:]]+@[0-9a-f]{40}[[:space:]]+\#[[:space:]]+v[0-9] ]]; then
    failures+=("$ci: unpinned or uncommented action: ${action#"${action%%[![:space:]]*}"}")
  fi
done < <(grep -E '^[[:space:]]*uses:' "$ci" || true)

dependabot=".github/dependabot.yml"
expect_file "$dependabot"
expect_pattern "$dependabot" '^version:[[:space:]]+2$' "Dependabot version must be 2"
if [[ -f "$dependabot" ]]; then
  [[ "$(grep -Ec 'package-ecosystem:[[:space:]]+\"?(swift|github-actions)\"?' "$dependabot" || true)" -eq 2 ]] \
    || failures+=("$dependabot: expected Swift and GitHub Actions updates")
  [[ "$(grep -Ec 'interval:[[:space:]]+\"?monthly\"?' "$dependabot" || true)" -eq 2 ]] \
    || failures+=("$dependabot: both update groups must be monthly")
  [[ "$(grep -Ec 'open-pull-requests-limit:[[:space:]]+5' "$dependabot" || true)" -eq 2 ]] \
    || failures+=("$dependabot: both update groups need PR limit 5")
fi

codeql=".github/workflows/codeql.yml"
expect_file "$codeql"
expect_pattern "$codeql" 'language:[[:space:]]+swift' "Swift language missing"
expect_pattern "$codeql" 'build-mode:[[:space:]]+manual' "Swift CodeQL must use a manual build"
expect_pattern "$codeql" 'runs-on:[[:space:]]+macos-26' "CodeQL runner must match the supported macOS image"
expect_pattern "$codeql" 'security-events:[[:space:]]+write' "security-events write permission missing"
expect_pattern "$codeql" 'packages:[[:space:]]+read' "packages read permission missing"
expect_pattern "$codeql" 'contents:[[:space:]]+read' "contents read permission missing"
expect_pattern "$codeql" '^[[:space:]]{2}pull_request:$' "pull request trigger missing"
expect_pattern "$codeql" '^[[:space:]]{2}push:$' "push trigger missing"
expect_pattern "$codeql" 'branches:[[:space:]]+\[main\]' "main branch push trigger missing"
expect_pattern "$codeql" 'cron:[[:space:]]+['"'"'"][^'"'"'"]+['"'"'"]' "weekly schedule missing"
expect_pattern "$codeql" 'xcodegen generate' "CodeQL build must generate the project"
expect_pattern "$codeql" 'CODE_SIGNING_ALLOWED=NO' "CodeQL build must not require signing credentials"
if [[ -f "$codeql" ]]; then
  while IFS= read -r action; do
    if [[ ! "$action" =~ ^[[:space:]]*uses:[[:space:]]+[^@[:space:]]+@[0-9a-f]{40}[[:space:]]+\#[[:space:]]+v[0-9] ]]; then
      failures+=("$codeql: unpinned or uncommented action: ${action#"${action%%[![:space:]]*}"}")
    fi
  done < <(grep -E '^[[:space:]]*uses:' "$codeql" || true)
fi

legacy_license="License""Secret"
trial_type="Trial""Manager"
lab_type="Pill""Lab"
lab_flag="--pill""-lab"
team_placeholder="YOUR""TEAMID"
for forbidden in "$legacy_license" "$trial_type" "$lab_type" "$lab_flag" "$team_placeholder"; do
  if git grep -q -F -- "$forbidden"; then
    failures+=("tracked files contain prohibited legacy/private marker")
  fi
done

reject_pattern project.yml '^[[:space:]]+DEVELOPMENT_TEAM:' "team identity must be supplied only by release tooling"
expect_pattern project.yml 'OTHER_CODE_SIGN_FLAGS:[[:space:]]+"--options=runtime"' "portable Debug signing must explicitly preserve hardened runtime"
expect_pattern project.yml 'ENABLE_DEBUG_DYLIB:[[:space:]]+NO' "portable hardened Debug builds must avoid an unloadable ad-hoc debug dylib"
expect_pattern project.yml 'CODE_SIGN_ENTITLEMENTS:[[:space:]]+Talkie/TalkieDebug\.entitlements' "portable hardened Debug tests must use test-host entitlements"
expect_file Talkie/TalkieDebug.entitlements
expect_pattern Talkie/TalkieDebug.entitlements 'com\.apple\.security\.cs\.disable-library-validation' "portable hardened Debug tests must allow XCTest bundle injection"
expect_pattern scripts/release.sh 'DEVELOPMENT_TEAM:\?' "release must require DEVELOPMENT_TEAM"
expect_pattern scripts/release.sh 'ExportOptions\.local\.plist' "release must generate a local export options file"
expect_pattern scripts/release.sh 'mkdir -p[[:space:]]+"\$\(dirname "\$EXPORT_OPTIONS"\)"' "release must create the local export options directory"
expect_pattern scripts/verify-project-config.sh 'scan-sensitive-content\.sh' "project verification must run the repository scanner"
expect_pattern scripts/verify-project-config.sh 'OTHER_CODE_SIGN_FLAGS' "project verification must enforce portable hardened-runtime flags"
expect_pattern scripts/verify-project-config.sh 'ENABLE_DEBUG_DYLIB' "project verification must enforce portable hardened Debug layout"
expect_pattern scripts/verify-project-config.sh 'TalkieDebug\.entitlements' "project verification must enforce portable Debug test-host entitlements"
for document in LICENSE PRIVACY.md SECURITY.md; do
  expect_pattern scripts/verify-project-config.sh "$document" "project verification must require $document"
done

scanner="scripts/scan-sensitive-content.sh"
expect_file "$scanner"
if [[ -x "$scanner" ]]; then
  fixture="$(mktemp -d "${TMPDIR:-/tmp}/talkie-public-scan.XXXXXX")"
  trap 'rm -rf "$fixture"' EXIT
  git -C "$fixture" init -q
  git -C "$fixture" config user.name "Talkie CI Test"
  git -C "$fixture" config user.email "ci-test@example.invalid"
  printf '%s\n' "safe fixture" > "$fixture/safe.txt"
  git -C "$fixture" add safe.txt
  git -C "$fixture" commit -qm "safe"

  if ! "$root/$scanner" --root "$fixture" --tracked-only >/dev/null 2>&1; then
    failures+=("$scanner: safe tracked fixture was rejected")
  fi

  assert_tracked_fixture_rejected() {
    local category="$1"
    local content="$2"
    local sentinel="fixture-value-that-must-not-be-printed"
    printf '%s\n' "${content}${sentinel}" > "$fixture/sensitive.txt"
    git -C "$fixture" add sensitive.txt
    local scan_output
    scan_output="$("$root/$scanner" --root "$fixture" --tracked-only 2>&1 || true)"
    if "$root/$scanner" --root "$fixture" --tracked-only >/dev/null 2>&1; then
      failures+=("$scanner: tracked $category fixture was accepted")
    fi
    if [[ "$scan_output" == *"$sentinel"* ]]; then
      failures+=("$scanner: scanner leaked a matched $category value")
    fi
    git -C "$fixture" reset -q -- sensitive.txt
    rm -f "$fixture/sensitive.txt"
  }

  private_header="-----BEGIN OPENSSH PRI""VATE KEY-----"
  openai_prefix="sk-""proj-abcdefghijklmnopqrstuvwxyz012345="
  openrouter_secret="sk-""or-v1-abcdefghijklmnopqrstuvwxyz012345="
  transcript_log='pri''nt("trans''cript content: \(trans''cript)") # '
  assert_tracked_fixture_rejected "legacy marker" "${legacy_license}="
  assert_tracked_fixture_rejected "private key" "${private_header} # "
  assert_tracked_fixture_rejected "OpenAI key" "$openai_prefix"
  assert_tracked_fixture_rejected "OpenRouter key" "$openrouter_secret"
  assert_tracked_fixture_rejected "transcript diagnostic" "$transcript_log"

  key_prefix="sk-""or-v1-"
  printf '%s\n' "${key_prefix}abcdefghijklmnopqrstuvwxyz012345" > "$fixture/untracked.txt"
  if "$root/$scanner" --root "$fixture" >/dev/null 2>&1; then
    failures+=("$scanner: current-tree sensitive fixture was accepted")
  fi
  if ! "$root/$scanner" --root "$fixture" --tracked-only >/dev/null 2>&1; then
    failures+=("$scanner: tracked-only mode scanned an untracked fixture")
  fi
fi

if ((${#failures[@]})); then
  printf 'public-readiness check failed (%d issue(s))\n' "${#failures[@]}" >&2
  printf ' - %s\n' "${failures[@]}" >&2
  exit 1
fi

echo "Public-readiness checks passed."
