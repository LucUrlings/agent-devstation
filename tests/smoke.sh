#!/usr/bin/env bash
set -euo pipefail

image=${IMAGE:-agent-devstation:ci}
name="devstation-smoke-$$"
java_name="devstation-java-smoke-$$"
cache_volume="devstation-cache-smoke-$$"
codex_name="devstation-codex-smoke-$$"
codex_volume="devstation-codex-home-smoke-$$"
workspace_volume="devstation-workspace-smoke-$$"
trap 'docker rm -f "$name" "$java_name" "$codex_name" >/dev/null 2>&1 || true; docker volume rm "$cache_volume" "$codex_volume" "$workspace_volume" >/dev/null 2>&1 || true' EXIT
trap 'echo "Smoke test failed at line $LINENO" >&2' ERR

wait_for_editor() {
  local editor_ready=false
  for _ in $(seq 1 180); do
    if docker exec -u dev "$name" curl -s --max-time 2 -o /dev/null http://127.0.0.1:8080/; then
      editor_ready=true
      break
    fi
    if [[ $(docker inspect -f '{{.State.Running}}' "$name") != true ]]; then
      docker logs "$name"
      return 1
    fi
    sleep 2
  done
  if [[ "$editor_ready" != true ]]; then
    docker logs "$name"
    return 1
  fi
}

wait_for_writable_node() {
  for _ in $(seq 1 60); do
    # npm can run before the entrypoint finishes giving dev write access.
    if docker exec -u dev "$name" bash -c 'npm --version >/dev/null && test -w /opt/sdk/node/current/bin && test -w /opt/sdk/node/current/lib/node_modules' >/dev/null 2>&1; then
      return 0
    fi
    if [[ $(docker inspect -f '{{.State.Running}}' "$name") != true ]]; then
      docker logs "$name"
      return 1
    fi
    sleep 2
  done
  docker logs "$name"
  return 1
}

bash tests/codex-wrapper.sh

# ChatGPT Remote's iOS folder picker resolves $HOME through an explicit
# read-only Codex sandbox. Verify the system path uses Codex's bundled
# bubblewrap binary, then exercise the sandbox with the same options as Compose.
test "$(docker compose config --format json | jq -r '.services["agent-devstation"].security_opt | join(",")')" = 'seccomp=unconfined,apparmor=unconfined'
docker run --rm "$image" bash -lc 'cmp /usr/bin/bwrap /opt/codex/packages/standalone/current/codex-resources/bwrap'
test "$(docker run --rm --security-opt seccomp=unconfined --security-opt apparmor=unconfined "$image" \
  codex sandbox -c 'sandbox_mode="read-only"' /bin/sh -lc 'cd "$HOME" && pwd -P')" = /home/dev
if docker run --rm --security-opt seccomp=unconfined --security-opt apparmor=unconfined "$image" \
  codex sandbox -c 'sandbox_mode="read-only"' /bin/sh -lc 'touch /workspaces/codex-read-only-probe' >/dev/null 2>&1; then
  echo 'Codex read-only sandbox allowed a workspace write' >&2
  exit 1
fi

# Compose can create ./workspaces as an empty root-owned bind source on Linux.
# The image must make that mount writable without taking over existing files.
docker volume create "$workspace_volume" >/dev/null
docker run --rm --mount "type=volume,src=$workspace_volume,dst=/workspaces,volume-nocopy" --entrypoint bash "$image" -lc \
  'chown root:root /workspaces; chmod 755 /workspaces'
docker run --rm --mount "type=volume,src=$workspace_volume,dst=/workspaces,volume-nocopy" "$image" bash -lc \
  'test "$HOME" = /home/dev && test -w "$HOME" && test -w /workspaces && git init -q --bare /tmp/smoke-origin.git && git clone -q /tmp/smoke-origin.git /workspaces/Watchtower && test -d /workspaces/Watchtower/.git'
docker run --rm --mount "type=volume,src=$workspace_volume,dst=/workspaces,volume-nocopy" --entrypoint bash "$image" -lc \
  'chown root:root /workspaces'
if output=$(docker run --rm --mount "type=volume,src=$workspace_volume,dst=/workspaces,volume-nocopy" "$image" true 2>&1); then
  echo 'Nonempty root-owned workspace was accepted unexpectedly' >&2
  exit 1
fi
[[ "$output" == *'/workspaces is not writable by dev'* ]] || { echo "$output" >&2; exit 1; }

# A home volume created by an older image can contain root-owned uv cache files
# even when the cache directory itself belongs to dev.
docker volume create "$cache_volume" >/dev/null
docker run --rm -v "$cache_volume:/home/dev" --entrypoint bash "$image" -lc \
  'mkdir -p /home/dev/.cache/uv; chown dev:dev /home/dev/.cache; touch /home/dev/.cache/uv/root-owned'
docker run --rm -v "$cache_volume:/home/dev" "$image" bash -lc \
  'test -w /home/dev/.cache/uv/root-owned && test -f /home/dev/.cache/.agent-devstation-ownership-v1'
docker run --rm -e AGENT_DEVSTATION_UID=1234 -e AGENT_DEVSTATION_GID=1234 "$image" bash -lc \
  'test "$(id -u):$(id -g)" = 1234:1234 && test -w /home/dev/.codex && test -w /workspaces'
docker run --rm -e AGENT_DEVSTATION_UID=33 -e AGENT_DEVSTATION_GID=20 "$image" bash -lc \
  'test "$(id -u):$(id -g)" = 33:20 && test -w /home/dev/.codex && test -w /workspaces'

docker run -d --name "$name" -e AGENT_DEVSTATION_VSCODE_EDITOR_ENABLED=false "$image" >/dev/null
sleep 3
docker exec -u dev "$name" bash -lc 'codex --version && claude --version && gh --version && ! command -v code-server'
docker exec -u dev "$name" bash -lc '
  set -euo pipefail
  codex login --help | grep -- "--device-auth" >/dev/null
  codex login --help | grep -- "--with-api-key" >/dev/null
  codex remote-control --help | grep "pair" >/dev/null
  claude auth --help | grep "login" >/dev/null
  claude --help | grep -- "--remote-control" >/dev/null
'
docker exec -u dev "$name" bash -lc 'for sdk in python python3 pip3 node npm npx corepack dotnet java javac go gofmt rustc cargo rustup; do if command -v "$sdk" >/dev/null; then echo "Unexpected SDK command: $sdk" >&2; exit 1; fi; done'
docker exec -u dev "$name" bash -lc '! curl -s --max-time 1 -o /dev/null http://127.0.0.1:8080/'
docker rm -f "$name" >/dev/null

# The home volume retains Codex daemon state and the user's start choice, but
# its package under /opt/codex belongs to the disposable container layer. A
# recreated container must bootstrap the package and resume Remote Control.
docker volume create "$codex_volume" >/dev/null
for generation in 1 2; do
  docker run -d --name "$codex_name" -v "$codex_volume:/home/dev" "$image" >/dev/null
  if [[ "$generation" == 1 ]]; then
    docker exec -u dev "$codex_name" bash -lc '
    set -euo pipefail
    status=0
    timeout 60s codex remote-control start >/tmp/codex-remote-start.log 2>&1 || status=$?
    [[ "$status" == 0 || "$status" == 1 ]] || { cat /tmp/codex-remote-start.log; exit 1; }
    test -x /home/dev/.codex/packages/app-server-daemon/current/bin/codex
    test -S /home/dev/.codex/app-server-control/app-server-control.sock
    touch /home/dev/.codex/.agent-devstation-remote-control-enabled
  '
  else
    # This polling shell exits explicitly; use a non-login shell so Ubuntu's
    # logout hook cannot replace its success status under set -e.
    docker exec -u dev "$codex_name" bash -c '
      set -euo pipefail
      for _ in $(seq 1 60); do
        test -S /home/dev/.codex/app-server-control/app-server-control.sock && exit 0
        sleep 1
      done
      exit 1
    '
    docker logs "$codex_name" 2>&1 | grep 'Resuming Codex Remote Control' >/dev/null
  fi
  docker rm -f "$codex_name" >/dev/null
done

if docker run --rm -e AGENT_DEVSTATION_SDK_NODE=24.x "$image" true >/dev/null 2>&1; then
  echo 'Version syntax accepted .x unexpectedly' >&2
  exit 1
fi
if docker run --rm -e AGENT_DEVSTATION_VSCODE_EDITOR_ENABLED=true "$image" true >/dev/null 2>&1; then
  echo 'Editor started without a password unexpectedly' >&2
  exit 1
fi

# Temurin's range API can return 21.0.12.1 when asked for 21.0.12. Verify
# that an exact selector picks the requested numeric release.
docker run -d --name "$java_name" -e AGENT_DEVSTATION_SDK_JAVA=21.0.12 "$image" >/dev/null
ready=false
for _ in $(seq 1 120); do
  if docker logs "$java_name" 2>&1 | grep '^java 21.0.12 ready$' >/dev/null; then ready=true; break; fi
  if [[ $(docker inspect -f '{{.State.Running}}' "$java_name") != true ]]; then docker logs "$java_name"; exit 1; fi
  sleep 2
done
[[ "$ready" == true ]] || { docker logs "$java_name"; exit 1; }
docker exec -u dev "$java_name" bash -lc 'java -version 2>&1 | grep -q "^openjdk version \"21.0.12\""'
docker rm -f "$java_name" >/dev/null

docker run -d --name "$name" \
  -e AGENT_DEVSTATION_SDK_PYTHON=3.14 -e AGENT_DEVSTATION_SDK_NODE=24 -e AGENT_DEVSTATION_SDK_DOTNET=10 \
  -e AGENT_DEVSTATION_SDK_JAVA=21 -e AGENT_DEVSTATION_SDK_GO=1.24 -e AGENT_DEVSTATION_SDK_RUST=1.85 \
  -e AGENT_DEVSTATION_VSCODE_EDITOR_ENABLED=true -e AGENT_DEVSTATION_VSCODE_PASSWORD=smoke-only-password \
  "$image" >/dev/null

ready=false
for _ in $(seq 1 180); do
  if docker logs "$name" 2>&1 | grep 'rust .* ready' >/dev/null; then ready=true; break; fi
  if [[ $(docker inspect -f '{{.State.Running}}' "$name") != true ]]; then docker logs "$name"; exit 1; fi
  sleep 10
done
[[ "$ready" == true ]] || { docker logs "$name"; exit 1; }

wait_for_editor

echo 'Checking SDK commands and editor login'
docker exec -u dev "$name" bash -lc 'python3 --version && node --version && dotnet --version && java -version && go version && rustc --version && cargo --version && test "$JAVA_HOME" = /opt/sdk/java/current && test "$DOTNET_ROOT" = /opt/sdk/dotnet/current'
docker exec -u dev "$name" code-server --version
docker exec -i -u dev -e DOTNET_CLI_TELEMETRY_OPTOUT=1 "$name" bash -s < tests/sdk-functional.sh
docker exec -u dev "$name" bash -lc 'curl -s -D - -o /dev/null http://127.0.0.1:8080/ | grep -qi "Location: ./login"'
docker exec -u dev "$name" bash -lc 'curl -s -c /tmp/editor-cookie -o /dev/null -d password=smoke-only-password http://127.0.0.1:8080/login; curl -s -b /tmp/editor-cookie -D - -o /dev/null http://127.0.0.1:8080/ | grep -qi "Location: ./?folder=/workspaces"'

# A hard interruption can leave extraction files beside an otherwise complete
# editor installation. Startup must clear them without downloading again.
docker exec -u root "$name" mkdir -p /opt/.agent-devstation-code-server-staging
before=$(docker logs "$name" 2>&1 | grep -c '^Installing ')
echo 'Restarting with installed SDKs and editor'
docker restart "$name" >/dev/null
wait_for_editor
after=$(docker logs "$name" 2>&1 | grep -c '^Installing ')
[[ "$before" == "$after" ]] || { echo 'Restart downloaded an SDK or editor again' >&2; exit 1; }
docker exec -u dev "$name" test ! -e /opt/.agent-devstation-code-server-staging
docker logs "$name" 2>&1 | grep '^Removing incomplete code-server download$' >/dev/null
docker logs "$name" 2>&1 | grep '^Found code-server .*; already installed$' >/dev/null

# A failed download can leave the current path without a working command. The
# next start must repair it instead of entering a permanent restart loop.
docker exec -u root "$name" mv /opt/sdk/node/current/bin/npm /opt/sdk/node/current/bin/npm.incomplete
docker restart "$name" >/dev/null
wait_for_writable_node
docker logs "$name" 2>&1 | grep '^Removing incomplete node installation$' >/dev/null

# An interrupted install can also leave a version directory before the
# current link is created. Startup must clear that partial directory.
docker exec -u root "$name" rm /opt/sdk/node/current
docker restart "$name" >/dev/null
wait_for_writable_node
repairs=$(docker logs "$name" 2>&1 | grep -c '^Removing incomplete node installation$')
[[ "$repairs" -ge 2 ]] || { echo 'Missing-current recovery did not clear the partial SDK' >&2; exit 1; }

# Go can still report its version when extraction stopped before its source
# tree was complete. Without the completion marker, startup must reinstall it.
docker exec -u root "$name" mv /opt/sdk/go/current/src /opt/sdk/go/current/src.incomplete
docker exec -u root "$name" mv /opt/sdk/go/.agent-devstation-complete /opt/sdk/go/.agent-devstation-incomplete
docker restart "$name" >/dev/null
recovered=false
for _ in $(seq 1 60); do
  if docker exec -u dev "$name" bash -lc 'test -d /opt/sdk/go/current/src && test -f /opt/sdk/go/.agent-devstation-complete && go version' >/dev/null 2>&1; then recovered=true; break; fi
  if [[ $(docker inspect -f '{{.State.Running}}' "$name") != true ]]; then docker logs "$name"; exit 1; fi
  sleep 2
done
[[ "$recovered" == true ]] || { docker logs "$name"; exit 1; }
docker logs "$name" 2>&1 | grep '^Removing incomplete go installation$' >/dev/null

# A changed selector replaces the installed version, and an empty selector
# removes it, even before a Compose recreation discards the container layer.
replacement=$(docker exec -u root -e HOME=/root -e AGENT_DEVSTATION_SDK_NODE=22 "$name" /usr/local/lib/agent-devstation/install-sdks.sh)
[[ "$replacement" == *'Uninstalling node '* && "$replacement" == *'Installing node 22'* ]] || { echo "$replacement" >&2; exit 1; }
docker exec -u dev "$name" bash -lc 'node --version | grep -q "^v22\."'
removal=$(docker exec -u root -e HOME=/root -e AGENT_DEVSTATION_SDK_NODE= "$name" /usr/local/lib/agent-devstation/install-sdks.sh)
[[ "$removal" == *'Uninstalling node (not selected)'* ]] || { echo "$removal" >&2; exit 1; }
docker exec -u dev "$name" bash -lc '! command -v node && test ! -e /opt/sdk/node'

docker rm -f "$name" >/dev/null
docker run -d --name "$name" "$image" >/dev/null
sleep 3
docker exec -u dev "$name" bash -lc 'for sdk in python python3 pip3 node npm npx corepack dotnet java javac go gofmt rustc cargo rustup code-server; do ! command -v "$sdk" || exit 1; done; test ! -e /opt/code-server'
