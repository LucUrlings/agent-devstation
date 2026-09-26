#!/usr/bin/env bash
set -euo pipefail

image=${IMAGE:-agent-devstation:ci}
name="devstation-smoke-$$"
cache_volume="devstation-cache-smoke-$$"
trap 'docker rm -f "$name" >/dev/null 2>&1 || true; docker volume rm "$cache_volume" >/dev/null 2>&1 || true' EXIT

# A home volume created by an older image can contain root-owned uv cache files
# even when the cache directory itself belongs to dev.
docker volume create "$cache_volume" >/dev/null
docker run --rm -v "$cache_volume:/home/dev" --entrypoint bash "$image" -lc \
  'mkdir -p /home/dev/.cache/uv; chown dev:dev /home/dev/.cache; touch /home/dev/.cache/uv/root-owned'
docker run --rm -v "$cache_volume:/home/dev" "$image" bash -lc \
  'test -w /home/dev/.cache/uv/root-owned && test -f /home/dev/.cache/.agent-devstation-ownership-v1'

docker run -d --name "$name" -e AGENT_DEVSTATION_VSCODE_EDITOR_ENABLED=false "$image" >/dev/null
sleep 3
docker exec -u dev "$name" bash -lc 'codex --version && claude --version && code-server --version'
docker exec -u dev "$name" bash -lc 'for sdk in python python3 pip3 node npm npx corepack dotnet java javac go gofmt rustc cargo rustup; do if command -v "$sdk" >/dev/null; then echo "Unexpected SDK command: $sdk" >&2; exit 1; fi; done'
docker exec -u dev "$name" bash -lc '! curl -s --max-time 1 -o /dev/null http://127.0.0.1:8080/'
docker rm -f "$name" >/dev/null

if docker run --rm -e AGENT_DEVSTATION_SDK_NODE=24.x "$image" true >/dev/null 2>&1; then
  echo 'Version syntax accepted .x unexpectedly' >&2
  exit 1
fi
if docker run --rm -e AGENT_DEVSTATION_VSCODE_EDITOR_ENABLED=true "$image" true >/dev/null 2>&1; then
  echo 'Editor started without a password unexpectedly' >&2
  exit 1
fi

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

editor_ready=false
for _ in $(seq 1 20); do
  if docker exec -u dev "$name" curl -s --max-time 2 -o /dev/null http://127.0.0.1:8080/; then editor_ready=true; break; fi
  sleep 1
done
[[ "$editor_ready" == true ]] || { docker logs "$name"; exit 1; }

docker exec -u dev "$name" bash -lc 'python3 --version && node --version && dotnet --version && java -version && go version && rustc --version && cargo --version && test "$JAVA_HOME" = /opt/sdk/java/current && test "$DOTNET_ROOT" = /opt/sdk/dotnet/current'
docker exec -i -u dev -e DOTNET_CLI_TELEMETRY_OPTOUT=1 "$name" bash -s < tests/sdk-functional.sh
docker exec -u dev "$name" bash -lc 'curl -s -D - -o /dev/null http://127.0.0.1:8080/ | grep -qi "Location: ./login"'
docker exec -u dev "$name" bash -lc 'curl -s -c /tmp/editor-cookie -o /dev/null -d password=smoke-only-password http://127.0.0.1:8080/login; curl -s -b /tmp/editor-cookie -D - -o /dev/null http://127.0.0.1:8080/ | grep -qi "Location: ./?folder=/workspaces"'

before=$(docker logs "$name" 2>&1 | grep -c '^Installing ')
docker restart "$name" >/dev/null
sleep 5
after=$(docker logs "$name" 2>&1 | grep -c '^Installing ')
[[ "$before" == "$after" ]] || { echo 'Restart downloaded an SDK again' >&2; exit 1; }

# A failed download can leave the current path without a working command. The
# next start must repair it instead of entering a permanent restart loop.
docker exec -u root "$name" mv /opt/sdk/node/current/bin/npm /opt/sdk/node/current/bin/npm.incomplete
docker restart "$name" >/dev/null
recovered=false
for _ in $(seq 1 60); do
  if docker exec -u dev "$name" npm --version >/dev/null 2>&1; then recovered=true; break; fi
  if [[ $(docker inspect -f '{{.State.Running}}' "$name") != true ]]; then docker logs "$name"; exit 1; fi
  sleep 2
done
[[ "$recovered" == true ]] || { docker logs "$name"; exit 1; }
docker logs "$name" 2>&1 | grep '^Removing incomplete node installation$' >/dev/null

# An interrupted install can also leave a version directory before the
# current link is created. Startup must clear that partial directory.
docker exec -u root "$name" rm /opt/sdk/node/current
docker restart "$name" >/dev/null
recovered=false
for _ in $(seq 1 60); do
  if docker exec -u dev "$name" npm --version >/dev/null 2>&1; then recovered=true; break; fi
  if [[ $(docker inspect -f '{{.State.Running}}' "$name") != true ]]; then docker logs "$name"; exit 1; fi
  sleep 2
done
[[ "$recovered" == true ]] || { docker logs "$name"; exit 1; }
repairs=$(docker logs "$name" 2>&1 | grep -c '^Removing incomplete node installation$')
[[ "$repairs" -ge 2 ]] || { echo 'Missing-current recovery did not clear the partial SDK' >&2; exit 1; }
docker exec -u dev "$name" bash -lc 'test -w /opt/sdk/node/current/bin && test -w /opt/sdk/node/current/lib/node_modules'

docker rm -f "$name" >/dev/null
docker run -d --name "$name" "$image" >/dev/null
sleep 3
docker exec -u dev "$name" bash -lc 'for sdk in python python3 pip3 node npm npx corepack dotnet java javac go gofmt rustc cargo rustup; do ! command -v "$sdk" || exit 1; done'
