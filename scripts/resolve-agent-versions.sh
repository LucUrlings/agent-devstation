#!/usr/bin/env bash
set -euo pipefail

# Resolve once per workflow run so both architecture builds use the same
# official stable releases. Exact build args also invalidate cached installs
# only when a stable release changes.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export GNUPGHOME="$tmp/gnupg"
mkdir -m 0700 "$GNUPGHOME"

fetch() {
  curl -fsSL --connect-timeout 15 --max-time 60 --retry 3 "$1" -o "$2"
}

fetch https://releases.openai.com/codex/channels/latest "$tmp/codex.json"
codex=$(jq -er '.tag_name | capture("^rust-v(?<version>[0-9]+\\.[0-9]+\\.[0-9]+)$").version' "$tmp/codex.json")

base=https://downloads.claude.ai/claude-code/apt/stable/dists/stable
fetch https://downloads.claude.ai/keys/claude-code.asc "$tmp/claude.asc"
fingerprint=$(gpg --batch --show-keys --with-colons "$tmp/claude.asc" | awk -F: '$1 == "fpr" { print $10; exit }')
[[ "$fingerprint" == 31DDDE24DDFAB679F42D7BD2BAA929FF1A7ECACE ]] || {
  echo 'Unexpected Claude apt signing key' >&2
  exit 1
}
gpg --batch --dearmor -o "$tmp/claude.gpg" "$tmp/claude.asc"
fetch "$base/InRelease" "$tmp/InRelease"
gpgv --keyring "$tmp/claude.gpg" "$tmp/InRelease" >&2

for arch in amd64 arm64; do
  path="main/binary-$arch/Packages.gz"
  hash=$(awk -v path="$path" '
    /^SHA256:$/ { in_sha256 = 1; next }
    in_sha256 && /^[^ ]/ { exit }
    in_sha256 && $3 == path { print $1; exit }
  ' "$tmp/InRelease")
  [[ "$hash" =~ ^[0-9a-f]{64}$ ]] || { echo "No SHA256 for $path" >&2; exit 1; }
  fetch "$base/$path" "$tmp/$arch.gz"
  printf '%s  %s\n' "$hash" "$tmp/$arch.gz" | sha256sum --check --status
  gzip -dc "$tmp/$arch.gz" | awk '
    /^Package: claude-code$/ { is_claude = 1; next }
    is_claude && /^Version: / { print $2; is_claude = 0 }
  ' | sort -u > "$tmp/$arch.versions"
done

claude=$(comm -12 "$tmp/amd64.versions" "$tmp/arm64.versions" | sort -V | tail -n 1)
[[ "$claude" =~ ^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+$ ]] || {
  echo 'No common stable Claude Code version for AMD64 and ARM64' >&2
  exit 1
}

printf 'codex=%s\nclaude=%s\n' "$codex" "$claude"
printf 'Resolved stable agents: Codex %s, Claude Code %s\n' "$codex" "$claude" >&2
