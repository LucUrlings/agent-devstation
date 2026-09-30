#!/usr/bin/env bash
set -euo pipefail

enabled=${AGENT_DEVSTATION_PLAYWRIGHT_CHROMIUM_ENABLED-false}
version=${AGENT_DEVSTATION_PLAYWRIGHT_VERSION-1.63.0}
root=/opt/playwright-browsers
stage=/opt/.agent-devstation-playwright-staging

if [[ "$enabled" == false ]]; then
  rm -rf -- "$root" "$stage"
  echo 'Playwright Chromium disabled; not installed'
  exit 0
fi

[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'AGENT_DEVSTATION_PLAYWRIGHT_VERSION must be an exact three-part version' >&2; exit 2; }
command -v npm >/dev/null || { echo 'Playwright Chromium requires AGENT_DEVSTATION_SDK_NODE' >&2; exit 2; }

has_browser() {
  [[ -d "$root" ]] && [[ -n "$(find "$root" -type f \( -name chrome -o -name chrome-headless-shell \) -executable -print -quit)" ]]
}

if [[ -f "$root/.agent-devstation-version" && "$(< "$root/.agent-devstation-version")" == "$version" ]] && has_browser; then
  echo "Found Playwright Chromium $version; already installed"
  exit 0
fi

rm -rf -- "$root" "$stage"
mkdir -p "$root" "$stage/npm-cache"
trap 'rm -rf -- "$stage"' EXIT
echo "Installing Playwright Chromium for Playwright $version"
PLAYWRIGHT_BROWSERS_PATH="$root" npm exec --yes --cache "$stage/npm-cache" \
  --package "playwright@$version" -- playwright install --with-deps chromium
has_browser || { echo 'Playwright Chromium installation did not produce a browser executable' >&2; exit 1; }
printf '%s\n' "$version" > "$root/.agent-devstation-version"
chown -R dev:dev "$root"
echo "Playwright Chromium $version ready"
