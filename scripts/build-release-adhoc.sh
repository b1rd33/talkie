#!/bin/bash
# Build Talkie's advanced, unsupported community preview.
#
# This path is deliberately ad-hoc signed and never contacts Apple's notary
# service or runs Gatekeeper assessment. Gatekeeper rejection is expected.
set -euo pipefail

repository_root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$repository_root"

fail() {
  echo "error: $1" >&2
  exit 1
}

version="$(
  sed -n 's/.*MARKETING_VERSION: *"\([^"]*\)".*/\1/p' project.yml | head -1
)"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || fail "could not read a semantic MARKETING_VERSION from project.yml"

archive="build/Talkie-community-preview.xcarchive"
app_source="$archive/Products/Applications/Talkie.app"
export_dir="build/export-community-preview"
app="$export_dir/Talkie.app"
preview_dir="build/community-preview-$version"
zip="$preview_dir/Talkie-$version-community-preview-adhoc.zip"
checksum_file="$preview_dir/SHA256SUMS"
verification_dir=""

cleanup() {
  local status=$?
  if [[ -n "$verification_dir" && -d "$verification_dir" ]]; then
    rm -rf -- "$verification_dir"
  fi
  exit "$status"
}
trap cleanup EXIT

rm -rf "$archive" "$export_dir" "$preview_dir"
mkdir -p "$preview_dir"

echo "==> Generating project"
xcodegen generate

echo "==> Archiving Talkie $version (community preview / ReleaseAdhoc)"
xcodebuild archive \
  -project Talkie.xcodeproj \
  -scheme Talkie \
  -configuration ReleaseAdhoc \
  -destination 'generic/platform=macOS' \
  -archivePath "$archive"

[[ -d "$app_source" ]] || fail "Xcode archive did not produce $app_source"
mkdir -p "$export_dir"
cp -R "$app_source" "$app"

# Re-sign inside-out so nested code and the outer app carry consistent ad-hoc
# seals. No Developer ID identity, secure timestamp, or hardened runtime is
# claimed by this community-preview path.
echo "==> Applying ad-hoc seals inside-out"
while IFS= read -r item; do
  codesign --force --timestamp=none -s - "$item"
done < <(
  find "$app/Contents" \
    \( -name "*.framework" -o -name "*.xpc" -o -name "*.app" -o -name "*.dylib" \) \
    -print \
    | awk '{ print length, $0 }' \
    | sort -rn \
    | cut -d' ' -f2-
)
codesign --force --timestamp=none -s - "$app"

for legal_notice in LICENSE NOTICE THIRD_PARTY_NOTICES.txt; do
  [[ -f "$app/Contents/Resources/$legal_notice" ]] \
    || fail "community preview app is missing legal notice: $legal_notice"
  cmp -s "$legal_notice" "$app/Contents/Resources/$legal_notice" \
    || fail "community preview app contains a modified legal notice: $legal_notice"
done

echo "==> Verifying ad-hoc code seals only"
codesign --verify --deep --strict --verbose=2 "$app"

echo "==> Packaging the community preview"
ditto -c -k --keepParent "$app" "$zip"

echo "==> Verifying the packaged community preview"
verification_dir="$(mktemp -d "build/community-preview-verification.XXXXXX")"
ditto -x -k "$zip" "$verification_dir"
packaged_app="$verification_dir/Talkie.app"
[[ -d "$packaged_app" ]] \
  || fail "community preview ZIP did not contain Talkie.app at its root"
for legal_notice in LICENSE NOTICE THIRD_PARTY_NOTICES.txt; do
  cmp -s "$legal_notice" "$packaged_app/Contents/Resources/$legal_notice" \
    || fail "packaged community preview contains a missing or modified legal notice: $legal_notice"
done
codesign --verify --deep --strict --verbose=2 "$packaged_app"
rm -rf -- "$verification_dir"
verification_dir=""

(
  cd "$preview_dir"
  shasum -a 256 "$(basename "$zip")" > "$(basename "$checksum_file")"
  shasum -a 256 -c "$(basename "$checksum_file")"
)

commit_sha="$(git rev-parse HEAD)"
echo
echo "Talkie community preview (advanced / unsupported):"
echo "  Version: $version"
echo "  Commit: $commit_sha"
echo "  Signing: ad-hoc code seals only"
echo "  Notarization: NOT notarized"
echo "  Gatekeeper: rejection is expected; no assessment was run or claimed"
echo "  ZIP: $zip"
echo "  Checksums: $checksum_file"
