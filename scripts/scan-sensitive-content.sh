#!/bin/bash
set -euo pipefail

repository_root=""
tracked_only=false

while (($#)); do
  case "$1" in
    --root)
      if (($# < 2)); then
        echo "error: --root requires a path" >&2
        exit 2
      fi
      repository_root="$2"
      shift 2
      ;;
    --tracked-only)
      tracked_only=true
      shift
      ;;
    *)
      echo "error: unknown argument" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$repository_root" ]]; then
  repository_root="$(cd "$(dirname "$0")/.." && pwd)"
else
  repository_root="$(cd "$repository_root" && pwd)"
fi

if ! git -C "$repository_root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "error: sensitive-content scan requires a Git work tree" >&2
  exit 2
fi

file_list="$(mktemp "${TMPDIR:-/tmp}/talkie-sensitive-files.XXXXXX")"
trap 'rm -f "$file_list"' EXIT

if [[ "$tracked_only" == true ]]; then
  git -C "$repository_root" ls-files -z --cached > "$file_list"
else
  git -C "$repository_root" ls-files -z --cached --others --exclude-standard > "$file_list"
fi

ruby - "$repository_root" "$file_list" <<'RUBY'
root, list_path = ARGV
paths = File.binread(list_path).split("\0").reject(&:empty?)

legacy_markers = [
  "License" + "Secret",
  "Trial" + "Manager",
  "Pill" + "Lab",
  "--pill" + "-lab",
  "YOUR" + "TEAMID",
]

openai_prefixes = [
  "sk-" + "proj-",
  "sk-" + "svcacct-",
]
openrouter_prefix = "sk-" + "or-v1-"

private_key_header = /-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----/
legacy_openai_key = /(?<![A-Za-z0-9_-])sk-[A-Za-z0-9]{20,}(?![A-Za-z0-9_-])/
modern_key = Regexp.union(
  openai_prefixes.map { |prefix| /#{Regexp.escape(prefix)}[A-Za-z0-9_-]{16,}/ } +
  [/#{Regexp.escape(openrouter_prefix)}[A-Za-z0-9_-]{16,}/]
)
logging_call = /
  (?:
    NSLog | debugPrint | print | os_log |
    logger\.(?:trace|debug|info|notice|warning|error|critical) |
    Logger\s*\([^)]*\)\s*\.(?:trace|debug|info|notice|warning|error|critical)
  )
  \s*\(
  (?:(?!\n\s*\n).){0,500}
  \b(?:transcript|rawText|cleanedText)\b
/imx

violations = 0
paths.each do |relative_path|
  path = File.join(root, relative_path)
  next unless File.file?(path)

  begin
    content = File.binread(path)
    next if content.include?("\0")
    content = content.force_encoding(Encoding::UTF_8)
    next unless content.valid_encoding?
  rescue SystemCallError
    next
  end

  violations += 1 if legacy_markers.any? { |marker| content.include?(marker) }
  violations += 1 if private_key_header.match?(content)
  violations += 1 if legacy_openai_key.match?(content) || modern_key.match?(content)
  violations += 1 if logging_call.match?(content)
end

if violations.positive?
  warn "error: sensitive-content scan failed (#{violations} violation(s)); matched content is intentionally redacted"
  exit 1
end

puts "Sensitive-content scan passed (#{paths.length} file(s))."
RUBY
