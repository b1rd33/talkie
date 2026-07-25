#!/bin/bash
set -euo pipefail

project_file="${1:-project.yml}"
manifest_file="${2:-Package.swift}"
lock_file="${3:-Package.resolved}"

if [[ ! -f "$project_file" || ! -f "$manifest_file" || ! -f "$lock_file" ]]; then
  echo "error: project.yml, the Dependabot Package.swift mirror, and Package.resolved are required" >&2
  exit 1
fi

if [[ "$(basename "$manifest_file")" != "Package.swift" ]]; then
  echo "error: dependency mirror manifest must be named Package.swift" >&2
  exit 1
fi

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/talkie-dependency-verification.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
mkdir -p "$work_dir/module-cache"

manifest_dir="$(cd "$(dirname "$manifest_file")" && pwd)"
if ! (
  cd "$manifest_dir"
  SWIFTPM_MODULECACHE_OVERRIDE="$work_dir/module-cache" \
    swift package --disable-sandbox dump-package
) >"$work_dir/package.json" 2>"$work_dir/swift-package.log"; then
  echo "error: unable to inspect the Dependabot Package.swift mirror" >&2
  cat "$work_dir/swift-package.log" >&2
  exit 1
fi

ruby -rjson -rpsych - "$project_file" "$work_dir/package.json" "$lock_file" <<'RUBY'
project_path, package_path, lock_path = ARGV
project = Psych.safe_load(File.read(project_path), aliases: true)
package = JSON.parse(File.read(package_path))
lock = JSON.parse(File.read(lock_path))

unless package.fetch("products").empty? && package.fetch("targets").empty?
  abort "error: Package.swift is metadata-only for Dependabot and must not define products or targets"
end

expected = project.fetch("packages").to_h do |name, specification|
  [
    name.downcase,
    {
      name: name,
      url: specification.fetch("url"),
      version: specification.fetch("exactVersion").to_s,
    },
  ]
end

actual = package.fetch("dependencies").to_h do |dependency|
  source = dependency.fetch("sourceControl").fetch(0)
  remote = source.fetch("location").fetch("remote").fetch(0)
  exact = source.fetch("requirement").fetch("exact").fetch(0)
  [
    source.fetch("identity").downcase,
    {
      url: remote.fetch("urlString"),
      version: exact.to_s,
    },
  ]
end

(expected.keys | actual.keys).sort.each do |identity|
  wanted = expected[identity]
  mirrored = actual[identity]
  display_name = wanted&.fetch(:name) || identity
  next if wanted && mirrored &&
          wanted.fetch(:url) == mirrored.fetch(:url) &&
          wanted.fetch(:version) == mirrored.fetch(:version)

  wanted_description = wanted ? "#{wanted.fetch(:url)} @ #{wanted.fetch(:version)}" : "absent"
  mirror_description = mirrored ? "#{mirrored.fetch(:url)} @ #{mirrored.fetch(:version)}" : "absent"
  abort <<~MESSAGE.strip
    error: dependency mirror mismatch for #{display_name}: project.yml has #{wanted_description}, Package.swift has #{mirror_description}. Update both files in the same change.
  MESSAGE
end

locked = lock.fetch("pins").to_h do |pin|
  [
    pin.fetch("identity").downcase,
    {
      url: pin.fetch("location"),
      version: pin.fetch("state").fetch("version").to_s,
    },
  ]
end

(expected.keys | locked.keys).sort.each do |identity|
  wanted = expected[identity]
  pinned = locked[identity]
  display_name = wanted&.fetch(:name) || identity
  next if wanted && pinned &&
          wanted.fetch(:url) == pinned.fetch(:url) &&
          wanted.fetch(:version) == pinned.fetch(:version)

  wanted_description = wanted ? "#{wanted.fetch(:url)} @ #{wanted.fetch(:version)}" : "absent"
  lock_description = pinned ? "#{pinned.fetch(:url)} @ #{pinned.fetch(:version)}" : "absent"
  abort <<~MESSAGE.strip
    error: dependency lockfile mismatch for #{display_name}: project.yml has #{wanted_description}, Package.resolved has #{lock_description}. Run 'swift package resolve' and commit the updated lockfile.
  MESSAGE
end

puts "Dependency mirror matches project.yml (#{expected.length} package(s))."
RUBY
