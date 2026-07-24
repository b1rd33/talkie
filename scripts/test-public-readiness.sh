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
reject_pattern "$ci" 'skip-testing:TalkieTests/ReleaseConfigurationTests' "deterministic CI must run release-configuration checks"

ui_step="$(awk '
  /^      - name: Run deterministic app UI suite$/ { capture = 1 }
  capture && /^      - name:/ && $0 !~ /Run deterministic app UI suite$/ { exit }
  capture { print }
' "$ci")"
[[ "$ui_step" =~ timeout-minutes:[[:space:]]+8 ]] \
  || failures+=("$ci: UI step must have an 8-minute timeout")
[[ "$ui_step" == *"-test-timeouts-enabled YES"* ]] \
  || failures+=("$ci: UI xcodebuild must enable per-test timeouts")
[[ "$ui_step" == *"-default-test-execution-time-allowance 60"* ]] \
  || failures+=("$ci: UI tests need a 60-second default execution allowance")
[[ "$ui_step" == *"-maximum-test-execution-time-allowance 120"* ]] \
  || failures+=("$ci: UI tests need a 120-second maximum execution allowance")
[[ "$ui_step" != *"CODE_SIGN_IDENTITY="* ]] \
  || failures+=("$ci: UI tests must use generated portable signing settings without command-line identity overrides")
[[ "$ui_step" == *'tee "$RUNNER_TEMP/xcodebuild-ui.log"'* ]] \
  || failures+=("$ci: UI output must always be captured in xcodebuild-ui.log")

diagnostic_steps="$(awk '
  /^      - name: Produce concise test summary$/ { capture = 1 }
  capture { print }
' "$ci")"
[[ "$diagnostic_steps" == *'xcodebuild-ui.log'* ]] \
  || failures+=("$ci: failure diagnostics must preserve the full UI log")
[[ "$diagnostic_steps" == *'xcodebuild-ui-tail.txt'* ]] \
  || failures+=("$ci: failure summary must include a concise UI log tail")
[[ "$diagnostic_steps" == *'GITHUB_STEP_SUMMARY'* ]] \
  || failures+=("$ci: UI failure details must be written to the job summary")

while IFS= read -r action; do
  if [[ ! "$action" =~ ^[[:space:]]*uses:[[:space:]]+[^@[:space:]]+@[0-9a-f]{40}[[:space:]]+\#[[:space:]]+v[0-9] ]]; then
    failures+=("$ci: unpinned or uncommented action: ${action#"${action%%[![:space:]]*}"}")
  fi
done < <(grep -E '^[[:space:]]*uses:' "$ci" || true)

dependabot=".github/dependabot.yml"
expect_file "$dependabot"
expect_file Package.swift
expect_file Package.resolved
expect_pattern Package.swift 'Dependabot dependency mirror' "dependency-only manifest must document its metadata purpose"
expect_pattern Package.swift '\.package\(url:[[:space:]]*"https://github\.com/soffes/HotKey",[[:space:]]+exact:[[:space:]]+"0\.2\.1"\)' "HotKey mirror dependency missing"
expect_pattern Package.swift '\.package\(url:[[:space:]]*"https://github\.com/FluidInference/FluidAudio",[[:space:]]+exact:[[:space:]]+"0\.15\.5"\)' "FluidAudio mirror dependency missing"
expect_file scripts/verify-dependency-mirror.sh
expect_pattern scripts/verify-dependency-mirror.sh 'swift package.*dump-package' "dependency mirror verification must inspect SwiftPM semantics"
expect_pattern scripts/verify-dependency-mirror.sh 'Package\.resolved' "dependency mirror verification must inspect the tracked SwiftPM lockfile"
expect_pattern scripts/verify-project-config.sh 'verify-dependency-mirror\.sh' "project verification must reject dependency-mirror drift"
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

bug_form=".github/ISSUE_TEMPLATE/bug.yml"
feature_form=".github/ISSUE_TEMPLATE/feature.yml"
issue_config=".github/ISSUE_TEMPLATE/config.yml"
pull_request_template=".github/pull_request_template.md"
privacy_warning="Do not paste API keys, transcripts, recordings, clipboard contents, crash logs containing personal paths, or other private data."

for template in "$bug_form" "$feature_form" "$issue_config" "$pull_request_template"; do
  expect_file "$template"
done

expect_pattern "$bug_form" "${privacy_warning//./\\.}" "missing the repository privacy warning"
expect_pattern "$feature_form" "${privacy_warning//./\\.}" "missing the repository privacy warning"

for checklist_line in \
  "- [ ] Tests cover the change and pass locally." \
  "- [ ] No live provider calls or production credentials are required by routine tests." \
  "- [ ] No transcript, selected text, clipboard content, recording, or API key is logged." \
  "- [ ] UI changes were checked with keyboard access, Reduce Motion, Increase Contrast, light mode, and dark mode." \
  "- [ ] User-facing behavior and privacy documentation are updated."
do
  expect_line "$pull_request_template" "$checklist_line"
done
for heading in "## Summary" "## Testing" "## Privacy"; do
  expect_line "$pull_request_template" "$heading"
done

if [[ -f "$bug_form" && -f "$feature_form" && -f "$issue_config" ]]; then
  ruby - "$bug_form" "$feature_form" "$issue_config" <<'RUBY' || failures+=("GitHub issue templates failed YAML/schema validation")
require "yaml"

def fail_schema(path, message)
  warn "#{path}: #{message}"
  exit 1
end

def load_yaml(path)
  YAML.safe_load(File.read(path), permitted_classes: [], permitted_symbols: [], aliases: false)
rescue Psych::Exception => error
  fail_schema(path, "invalid YAML: #{error.message.lines.first.strip}")
end

def validate_form(path, required_ids)
  form = load_yaml(path)
  fail_schema(path, "top level must be a mapping") unless form.is_a?(Hash)
  %w[name description].each do |key|
    fail_schema(path, "#{key} must be a non-empty string") unless form[key].is_a?(String) && !form[key].strip.empty?
  end
  fail_schema(path, "title must be a string") if form.key?("title") && !form["title"].is_a?(String)
  %w[labels assignees].each do |key|
    next unless form.key?(key)
    value = form[key]
    fail_schema(path, "#{key} must be an array of strings") unless value.is_a?(Array) && value.all? { |item| item.is_a?(String) }
  end

  body = form["body"]
  fail_schema(path, "body must be a non-empty array") unless body.is_a?(Array) && !body.empty?
  seen_ids = []
  allowed_types = %w[markdown input dropdown textarea checkboxes]
  body.each_with_index do |element, index|
    fail_schema(path, "body item #{index} must be a mapping") unless element.is_a?(Hash)
    type = element["type"]
    fail_schema(path, "body item #{index} has unsupported type") unless allowed_types.include?(type)
    attributes = element["attributes"]
    fail_schema(path, "body item #{index} attributes must be a mapping") unless attributes.is_a?(Hash)

    if type == "markdown"
      fail_schema(path, "markdown item #{index} needs a non-empty value") unless attributes["value"].is_a?(String) && !attributes["value"].strip.empty?
      next
    end

    id = element["id"]
    fail_schema(path, "body item #{index} needs a valid id") unless id.is_a?(String) && id.match?(/\A[A-Za-z0-9_-]+\z/)
    fail_schema(path, "duplicate id #{id}") if seen_ids.include?(id)
    seen_ids << id
    fail_schema(path, "#{id} needs a non-empty label") unless attributes["label"].is_a?(String) && !attributes["label"].strip.empty?

    validations = element.fetch("validations", {})
    fail_schema(path, "#{id} validations must be a mapping") unless validations.is_a?(Hash)
    if validations.key?("required") && ![true, false].include?(validations["required"])
      fail_schema(path, "#{id} required validation must be boolean")
    end

    if type == "dropdown"
      options = attributes["options"]
      fail_schema(path, "#{id} dropdown needs at least two string options") unless options.is_a?(Array) && options.length >= 2 && options.all? { |option| option.is_a?(String) && !option.strip.empty? }
      if attributes.key?("multiple") && ![true, false].include?(attributes["multiple"])
        fail_schema(path, "#{id} multiple attribute must be boolean")
      end
    elsif type == "checkboxes"
      options = attributes["options"]
      valid_options = options.is_a?(Array) && !options.empty? && options.all? do |option|
        option.is_a?(Hash) &&
          option["label"].is_a?(String) && !option["label"].strip.empty? &&
          (!option.key?("required") || [true, false].include?(option["required"]))
      end
      fail_schema(path, "#{id} checkboxes need valid options") unless valid_options
    end
  end

  missing = required_ids - seen_ids
  fail_schema(path, "missing required field ids: #{missing.join(", ")}") unless missing.empty?
  required_ids.each do |id|
    element = body.find { |item| item["id"] == id }
    fail_schema(path, "#{id} must be required") unless element.dig("validations", "required") == true
  end
end

bug_path, feature_path, config_path = ARGV
validate_form(bug_path, %w[version macos_version architecture engine_mode expected actual steps regression])
validate_form(feature_path, %w[problem proposed_behavior privacy_impact local_offline_impact alternatives])

feature_ids = load_yaml(feature_path).fetch("body").map { |item| item["id"] }.compact
expected_order = %w[problem proposed_behavior privacy_impact local_offline_impact alternatives]
positions = expected_order.map { |id| feature_ids.index(id) }
fail_schema(feature_path, "feature questions must remain in problem-first order") unless positions == positions.sort

config = load_yaml(config_path)
fail_schema(config_path, "config top level must be a mapping") unless config.is_a?(Hash)
fail_schema(config_path, "blank issues must be disabled") unless config["blank_issues_enabled"] == false
links = config["contact_links"]
fail_schema(config_path, "contact_links must contain Discussions and private security guidance") unless links.is_a?(Array) && links.length == 2
expected_urls = [
  "https://github.com/b1rd33/talkie/discussions",
  "https://github.com/b1rd33/talkie/security/policy"
]
actual_urls = links.map { |link| link.is_a?(Hash) ? link["url"] : nil }
fail_schema(config_path, "contact links must use stable repository URLs") unless actual_urls == expected_urls
links.each_with_index do |link, index|
  fail_schema(config_path, "contact link #{index} must have name, url, and about strings") unless %w[name url about].all? { |key| link[key].is_a?(String) && !link[key].strip.empty? }
end
security_link = links.last
unless security_link["name"].match?(/security|vulnerability/i) &&
       security_link["about"].match?(/private/i) &&
       !security_link["about"].match?(/public issue/i)
  fail_schema(config_path, "security contact must direct reporters to private vulnerability reporting")
end

[bug_path, feature_path].each do |path|
  content = File.read(path)
  forbidden_prompts = [
    /paste your API key here/i,
    /attach (?:your )?transcript/i,
    /upload (?:a |your )?recording/i,
    /provide (?:your )?clipboard contents/i
  ]
  fail_schema(path, "requests secrets or private content") if forbidden_prompts.any? { |pattern| content.match?(pattern) }
end
RUBY
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
expect_file Talkie/TalkieDebug.entitlements
expect_pattern scripts/release.sh 'DEVELOPMENT_TEAM:\?' "release must require DEVELOPMENT_TEAM"
expect_pattern scripts/release.sh 'ExportOptions\.local\.plist' "release must generate a local export options file"
expect_pattern scripts/release.sh 'mkdir -p[[:space:]]+"\$\(dirname "\$EXPORT_OPTIONS"\)"' "release must create the local export options directory"
release_generate_line="$(grep -n -m1 'xcodegen generate' scripts/release.sh | cut -d: -f1 || true)"
release_verify_line="$(grep -n -m1 'scripts/verify-project-config\.sh' scripts/release.sh | cut -d: -f1 || true)"
if [[ -z "$release_generate_line" || -z "$release_verify_line" ||
      "$release_generate_line" -ge "$release_verify_line" ]]; then
  failures+=("scripts/release.sh: must generate the project before semantic configuration verification")
fi
expect_pattern scripts/verify-project-config.sh 'scan-sensitive-content\.sh' "project verification must run the repository scanner"
expect_pattern scripts/verify-project-config.sh 'xcodebuild' "signing verification must inspect the generated Xcode project"
expect_pattern scripts/verify-project-config.sh '-showBuildSettings' "signing verification must inspect generated build settings"
expect_pattern scripts/verify-project-config.sh '-json' "generated build settings must be parsed as structured JSON"
expect_pattern scripts/verify-project-config.sh 'assert_setting.*Debug.*OTHER_CODE_SIGN_FLAGS.*--options=runtime' "Debug runtime signing flag must be verified"
expect_pattern scripts/verify-project-config.sh 'assert_setting.*Release.*ENABLE_HARDENED_RUNTIME.*YES' "Release hardened runtime must be verified"
expect_pattern scripts/verify-project-config.sh 'assert_setting.*Release.*CODE_SIGN_IDENTITY.*Developer ID Application' "Release signing identity must be verified"
expect_pattern scripts/verify-project-config.sh 'assert_entitlement.*Talkie/TalkieDebug\.entitlements.*disable-library-validation.*true' "Debug XCTest entitlement must be verified"
expect_pattern scripts/verify-project-config.sh 'reject_entitlement.*Talkie/Talkie\.entitlements.*disable-library-validation' "Release library validation must remain enabled"
reject_pattern scripts/verify-project-config.sh "require_line 'ENABLE_HARDENED_RUNTIME|require_line 'OTHER_CODE_SIGN_FLAGS|require_line 'CODE_SIGN_IDENTITY" "signing checks must not grep unscoped project text"
for document in LICENSE PRIVACY.md SECURITY.md; do
  expect_pattern scripts/verify-project-config.sh "$document" "project verification must require $document"
done

if [[ -x scripts/verify-dependency-mirror.sh && -f Package.swift ]]; then
  mirror_fixture="$(mktemp -d "${TMPDIR:-/tmp}/talkie-dependency-mirror.XXXXXX")"
  cp Package.swift "$mirror_fixture/Package.swift"
  cp Package.resolved "$mirror_fixture/Package.resolved"
  cp project.yml "$mirror_fixture/project.yml"
  perl -0pi -e 's/0[.]2[.]1/9.9.9/' "$mirror_fixture/Package.swift"
  mirror_output="$(
    scripts/verify-dependency-mirror.sh \
      "$mirror_fixture/project.yml" "$mirror_fixture/Package.swift" 2>&1 || true
  )"
  if scripts/verify-dependency-mirror.sh \
      "$mirror_fixture/project.yml" "$mirror_fixture/Package.swift" >/dev/null 2>&1; then
    failures+=("scripts/verify-dependency-mirror.sh: accepted a diverged HotKey version")
  fi
  [[ "$mirror_output" == *"dependency mirror mismatch for HotKey"* ]] \
    || failures+=("scripts/verify-dependency-mirror.sh: mismatch error must identify HotKey")

  cp Package.swift "$mirror_fixture/Package.swift"
  perl -0pi -e 's/0[.]2[.]1/9.9.9/' "$mirror_fixture/Package.resolved"
  lock_output="$(
    scripts/verify-dependency-mirror.sh \
      "$mirror_fixture/project.yml" "$mirror_fixture/Package.swift" \
      "$mirror_fixture/Package.resolved" 2>&1 || true
  )"
  if scripts/verify-dependency-mirror.sh \
      "$mirror_fixture/project.yml" "$mirror_fixture/Package.swift" \
      "$mirror_fixture/Package.resolved" >/dev/null 2>&1; then
    failures+=("scripts/verify-dependency-mirror.sh: accepted a diverged HotKey lockfile version")
  fi
  [[ "$lock_output" == *"lockfile mismatch for HotKey"* ]] \
    || failures+=("scripts/verify-dependency-mirror.sh: lockfile mismatch error must identify HotKey")
  rm -rf "$mirror_fixture"
fi

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
