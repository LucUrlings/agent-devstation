#!/usr/bin/env bash
set -euo pipefail

enabled=${AGENT_DEVSTATION_DOCKER_CLI_ENABLED-false}
version=29.8.1
compose_version=5.5.1
buildx_version=0.37.1
root=/opt/agent-devstation-docker-cli
stage=/opt/.agent-devstation-docker-cli-staging
plugin_dir=/usr/local/libexec/docker/cli-plugins

unlink_tools() {
  rm -f /usr/local/bin/docker "$plugin_dir/docker-compose" "$plugin_dir/docker-buildx"
}

if [[ -e "$stage" || -L "$stage" ]]; then
  echo 'Removing incomplete Docker CLI download'
  rm -rf -- "$stage"
fi

if [[ "$enabled" == false ]]; then
  unlink_tools
  rm -rf -- "$root" "$stage"
  echo 'Docker CLI disabled; not installed'
  exit 0
fi

if [[ -f "$root/.version" && "$(< "$root/.version")" == "$version $compose_version $buildx_version" \
  && -x "$root/docker" && -x "$root/docker-compose" && -x "$root/docker-buildx" ]]; then
  echo "Found Docker CLI $version; already installed"
else
  rm -rf -- "$root" "$stage"
  arch=$(dpkg --print-architecture)
  case "$arch" in
    amd64)
      static_arch=x86_64
      docker_sha=d8db66739d2e28d4933786d73e918d9be643a67fbd835db1bf740d650a259e70
      compose_arch=x86_64
      compose_sha=db1889184726840f75c4f9c001048430d4f25b3be3cb084d3ddd762bc0aed576
      buildx_sha=9447199cdb435f25880548343c128a4b6650e8891ee598905d8d29d39a8e359b
      ;;
    arm64)
      static_arch=aarch64
      docker_sha=667395fbffab52901b80181dfbb39ea76da2fbd7642c4fbddd24e42146b07b48
      compose_arch=aarch64
      compose_sha=732e3a84c1a0f67256ce80bc2598a24546b10ca05f9faa97efceb1171ece2ef7
      buildx_sha=e5cc9fe3bbff5cbc91230981f7860e06076110730a2db997082652199042a1f2
      ;;
    *) echo "Unsupported Docker CLI architecture: $arch" >&2; exit 1 ;;
  esac

  mkdir -p "$stage/release"
  trap 'rm -rf -- "$stage"' EXIT
  fetch() { curl -fsSL --retry 5 --retry-all-errors --retry-delay 2 "$@"; }
  check_sha() { printf '%s  %s\n' "$1" "$2" | sha256sum -c - >/dev/null; }
  echo "Installing Docker CLI $version, Compose $compose_version, and Buildx $buildx_version"
  fetch "https://download.docker.com/linux/static/stable/$static_arch/docker-$version.tgz" -o "$stage/docker.tgz"
  check_sha "$docker_sha" "$stage/docker.tgz"
  tar -xzf "$stage/docker.tgz" --strip-components=1 -C "$stage/release" docker/docker
  fetch "https://github.com/docker/compose/releases/download/v$compose_version/docker-compose-linux-$compose_arch" -o "$stage/release/docker-compose"
  check_sha "$compose_sha" "$stage/release/docker-compose"
  fetch "https://github.com/docker/buildx/releases/download/v$buildx_version/buildx-v$buildx_version.linux-$arch" -o "$stage/release/docker-buildx"
  check_sha "$buildx_sha" "$stage/release/docker-buildx"
  chmod 0755 "$stage/release/docker" "$stage/release/docker-compose" "$stage/release/docker-buildx"
  printf '%s %s %s\n' "$version" "$compose_version" "$buildx_version" > "$stage/release/.version"
  mv "$stage/release" "$root"
fi

mkdir -p "$plugin_dir"
ln -sfn "$root/docker" /usr/local/bin/docker
ln -sfn "$root/docker-compose" "$plugin_dir/docker-compose"
ln -sfn "$root/docker-buildx" "$plugin_dir/docker-buildx"
docker --version
docker compose version
docker buildx version
