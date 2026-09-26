#!/usr/bin/env bash
set -euo pipefail

# Keep the optional editor in the disposable container layer, like SDKs.
# Its bundled Node runtime stays private to code-server, outside SDK PATH.
version=4.138.0
root=/opt/code-server
editor_bin="$root/bin/code-server"
version_file="$root/.agent-devstation-version"
stage=/opt/.agent-devstation-code-server-staging

if [[ -e "$stage" || -L "$stage" ]]; then
  echo 'Removing incomplete code-server download'
  rm -rf -- "$stage"
fi

installed_version() {
  HOME=/root "$1" --version | awk '$1 ~ /^[0-9]+\.[0-9]+\.[0-9]+$/ { print $1; exit }'
}

if [[ -f "$version_file" && "$(< "$version_file")" == "$version" && -x "$editor_bin" ]] \
  && [[ "$(installed_version "$editor_bin")" == "$version" ]]; then
  ln -sfn "$editor_bin" /usr/local/bin/code-server
  echo "Found code-server $version; already installed"
  exit 0
fi

if [[ -e "$root" || -L "$root" ]]; then
  if [[ -f "$version_file" ]]; then
    echo "Uninstalling code-server $(< "$version_file") (requested $version)"
  else
    echo 'Removing incomplete code-server installation'
  fi
  rm -rf -- "$root"
fi
rm -f -- /usr/local/bin/code-server

arch=$(dpkg --print-architecture)
case "$arch" in
  amd64|arm64) ;;
  *) echo "Unsupported code-server architecture: $arch" >&2; exit 1 ;;
esac

mkdir "$stage"
trap 'rm -rf -- "$stage"' EXIT
echo "Installing code-server $version"
curl -fsSL --retry 5 --retry-all-errors --retry-delay 2 \
  "https://github.com/coder/code-server/releases/download/v${version}/code-server-${version}-linux-${arch}.tar.gz" \
  -o "$stage/code-server.tar.gz"
mkdir "$stage/release"
tar -xzf "$stage/code-server.tar.gz" --strip-components=1 -C "$stage/release"
[[ -x "$stage/release/bin/code-server" ]] || { echo 'code-server archive has no executable' >&2; exit 1; }
installed=$(installed_version "$stage/release/bin/code-server")
[[ "$installed" == "$version" ]] || { echo "Unexpected code-server version: $installed" >&2; exit 1; }
mv "$stage/release" "$root"
printf '%s\n' "$version" > "$version_file"
ln -sfn "$editor_bin" /usr/local/bin/code-server
echo "code-server $version ready"
