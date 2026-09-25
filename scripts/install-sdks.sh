#!/usr/bin/env bash
set -euo pipefail

# Container writable layers are discarded on Compose recreation. A normal restart
# keeps this layer, so matching installs are reused without a network request.
sdk_root=/opt/sdk

valid_version() {
  [[ "$1" =~ ^[0-9]+(\.[0-9]+){0,2}(\.x)?$ ]]
}

requested_prefix() {
  printf '%s' "${1%.x}"
}

matches() {
  local actual=$1 requested
  requested=$(requested_prefix "$2")
  [[ "$actual" == "$requested" || "$actual" == "$requested".* ]]
}

installed_version() {
  local name=$1
  [[ -e "$sdk_root/$name/current" ]] || return 1
  case "$name" in
    python) "$sdk_root/python/current/bin/python3" -c 'import platform; print(platform.python_version())' ;;
    node) "$sdk_root/node/current/bin/node" --version | sed 's/^v//' ;;
    dotnet) "$sdk_root/dotnet/current/dotnet" --version ;;
    java) "$sdk_root/java/current/bin/java" -version 2>&1 | sed -nE '1s/.*version "([0-9.]+).*/\1/p' ;;
    go) "$sdk_root/go/current/bin/go" version | sed -nE 's/.* go([0-9.]+) .*/\1/p' ;;
    rust) "$sdk_root/rust/current/bin/rustc" --version | awk '{print $2}' ;;
  esac
}

install_python() {
  UV_PYTHON_BIN_DIR=/tmp/devstation-python-bin uv python install --install-dir "$sdk_root/python" "$(requested_prefix "$1")"
  local interpreter target
  interpreter=$(uv python find --managed-python --system "$(requested_prefix "$1")")
  target=$(dirname "$(dirname "$(readlink -f "$interpreter")")")
  ln -s "$target" "$sdk_root/python/current"
  ln -sf python3 "$sdk_root/python/current/bin/python"
  # This copy is the container's selected global Python, not uv's own tool
  # environment. Permit pip in it just as with a conventional /opt install.
  rm -f "$("$sdk_root/python/current/bin/python3" -c 'import sysconfig; print(sysconfig.get_path("stdlib"))')/EXTERNALLY-MANAGED"
  "$sdk_root/python/current/bin/python3" -m ensurepip --upgrade
}

install_node() {
  local version arch
  version=$(curl -fsSL https://nodejs.org/dist/index.json | jq -r --arg p "$(requested_prefix "$1")" '[.[].version | ltrimstr("v") | select(. == $p or startswith($p + "."))][0] // empty')
  [[ -n "$version" ]] || { echo "No Node.js release matches $1" >&2; return 1; }
  arch=$(dpkg --print-architecture)
  [[ "$arch" == amd64 ]] && arch=x64
  mkdir -p "$sdk_root/node/$version"
  curl -fsSL "https://nodejs.org/dist/v${version}/node-v${version}-linux-${arch}.tar.xz" | tar -xJ --strip-components=1 -C "$sdk_root/node/$version"
  ln -s "$version" "$sdk_root/node/current"
}

install_dotnet() {
  local version=$1
  curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh
  mkdir -p "$sdk_root/dotnet/current"
  if [[ "$version" =~ ^[0-9]+(\.[0-9]+)?(\.x)?$ ]]; then
    local channel
    channel=$(requested_prefix "$version")
    [[ "$channel" == *.* ]] || channel="$channel.0"
    /bin/bash /tmp/dotnet-install.sh --channel "$channel" --install-dir "$sdk_root/dotnet/current" --no-path
  else
    /bin/bash /tmp/dotnet-install.sh --version "$version" --install-dir "$sdk_root/dotnet/current" --no-path
  fi
  rm /tmp/dotnet-install.sh
}

install_java() {
  local major arch
  major=${1%%.*}
  arch=$(dpkg --print-architecture)
  [[ "$arch" == amd64 ]] && arch=x64
  [[ "$arch" == arm64 ]] && arch=aarch64
  mkdir -p "$sdk_root/java/$1"
  curl -fsSL "https://api.adoptium.net/v3/binary/latest/${major}/ga/linux/${arch}/jdk/hotspot/normal/eclipse" | tar -xz --strip-components=1 -C "$sdk_root/java/$1"
  ln -s "$1" "$sdk_root/java/current"
}

install_go() {
  local version arch
  version=$(curl -fsSL 'https://go.dev/dl/?mode=json&include=all' | jq -r --arg p "$(requested_prefix "$1")" '[.[].version | ltrimstr("go") | select(. == $p or startswith($p + "."))][0] // empty')
  [[ -n "$version" ]] || { echo "No Go release matches $1" >&2; return 1; }
  arch=$(dpkg --print-architecture)
  mkdir -p "$sdk_root/go/$version"
  curl -fsSL "https://go.dev/dl/go${version}.linux-${arch}.tar.gz" | tar -xz --strip-components=1 -C "$sdk_root/go/$version"
  ln -s "$version" "$sdk_root/go/current"
}

install_rust() {
  mkdir -p "$CARGO_HOME" "$RUSTUP_HOME"
  curl -fsSL https://sh.rustup.rs -o /tmp/rustup-init.sh
  HOME=/root sh /tmp/rustup-init.sh -y --no-modify-path --profile default --default-toolchain "$(requested_prefix "$1")"
  rm /tmp/rustup-init.sh
}

declare -A requests=(
  [python]="${SDK_PYTHON:-}" [node]="${SDK_NODE:-}"
  [dotnet]="${SDK_DOTNET:-}" [java]="${SDK_JAVA:-}"
  [go]="${SDK_GO:-}" [rust]="${SDK_RUST:-}"
)

for name in python node dotnet java go rust; do
  version=${requests[$name]}
  [[ -z "$version" ]] && continue
  valid_version "$version" || { echo "Invalid SDK_${name^^} version: $version" >&2; exit 2; }
  if [[ "$name" == java && ! "$version" =~ ^[0-9]+$ ]]; then
    echo 'SDK_JAVA accepts a major version such as 21' >&2
    exit 2
  fi
done

for name in python node dotnet java go rust; do
  version=${requests[$name]}
  [[ -z "$version" ]] && continue
  current=$(installed_version "$name" || true)
  if [[ -n "$current" ]] && matches "$current" "$version"; then
    echo "$name $current already installed"
    continue
  fi
  if [[ -e "$sdk_root/$name/current" ]]; then
    echo "Installed $name version $current does not match $version; recreate the container" >&2
    exit 2
  fi
  echo "Installing $name $version"
  "install_$name" "$version"
  current=$(installed_version "$name")
  matches "$current" "$version" || { echo "$name installed $current, expected $version" >&2; exit 2; }
  echo "$name $current ready"
done
