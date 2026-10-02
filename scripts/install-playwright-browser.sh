#!/usr/bin/env bash
set -euo pipefail

enabled=${AGENT_DEVSTATION_PLAYWRIGHT_CHROMIUM_ENABLED-false}
version=${AGENT_DEVSTATION_PLAYWRIGHT_VERSION-1.63.0}
root=/opt/playwright-browsers
stage=/opt/.agent-devstation-playwright-staging
package_root="$root/.agent-devstation-installer"
executables_file="$root/.agent-devstation-executables"

if [[ -e "$stage" || -L "$stage" ]]; then
  echo 'Removing incomplete Playwright download'
  rm -rf -- "$stage"
fi

if [[ "$enabled" == false ]]; then
  rm -rf -- "$root" "$stage"
  # Project-owned installs use the normal, persisted user cache. Removing
  # this link on later startups never removes the user's browser files.
  user_cache=/home/dev/.cache/ms-playwright
  mkdir -p "$user_cache"
  chown dev:dev /home/dev/.cache "$user_cache"
  ln -s "$user_cache" "$root"
  echo 'Playwright Chromium disabled; not installed'
  exit 0
fi

[[ "${PLAYWRIGHT_BROWSERS_PATH-$root}" == "$root" ]] || {
  echo 'PLAYWRIGHT_BROWSERS_PATH must be /opt/playwright-browsers when AGENT_DEVSTATION_PLAYWRIGHT_CHROMIUM_ENABLED=true; disable shared Chromium to manage a custom browser cache' >&2
  exit 2
}
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo 'AGENT_DEVSTATION_PLAYWRIGHT_VERSION must be an exact three-part version' >&2; exit 2; }
command -v npm >/dev/null || { echo 'Playwright Chromium requires AGENT_DEVSTATION_SDK_NODE' >&2; exit 2; }

has_browser() {
  [[ -f "$package_root/node_modules/playwright-core/browsers.json" && -s "$executables_file" ]] || return 1
  local executable
  while IFS= read -r executable; do
    [[ -x "$root/$executable" ]] || return 1
  done < "$executables_file"
}

if [[ -f "$root/.agent-devstation-version" && "$(< "$root/.agent-devstation-version")" == "$version" ]] && has_browser; then
  echo "Found Playwright Chromium $version; already installed"
  exit 0
fi

rm -rf -- "$root" "$stage"
mkdir -p "$root" "$stage/npm-cache"
trap 'rm -rf -- "$stage"' EXIT
echo "Installing Playwright Chromium for Playwright $version"
# Keep the installer package at a stable, private path. Playwright registers
# it as a browser user, so another project's cleanup cannot collect these
# shared browsers. No command or package is installed globally.
npm install --prefix "$package_root" --ignore-scripts --no-audit --no-fund \
  --cache "$stage/npm-cache" "playwright-core@$version"
PLAYWRIGHT_BROWSERS_PATH="$root" node "$package_root/node_modules/playwright-core/cli.js" install --with-deps chromium
find "$root" -path "$package_root" -prune -o -type f -executable -printf '%P\n' > "$executables_file"
has_browser || { echo 'Playwright Chromium installation did not produce a browser executable' >&2; exit 1; }
chown -R dev:dev "$root"
printf '%s\n' "$version" > "$root/.agent-devstation-version"
echo "Playwright Chromium $version ready"
