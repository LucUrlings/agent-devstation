#!/usr/bin/env bash
set -euo pipefail

image=${IMAGE:-agent-devstation:ci}
name="devstation-smoke-$$"
trap 'docker rm -f "$name" >/dev/null 2>&1 || true' EXIT

docker run -d --name "$name" -e VSCODE_EDITOR_ENABLED=false "$image" >/dev/null
sleep 3
docker exec -u dev "$name" bash -lc 'codex --version && claude --version && code-server --version'
docker exec -u dev "$name" bash -lc 'for sdk in python python3 pip3 node npm npx corepack dotnet java javac go gofmt rustc cargo rustup; do if command -v "$sdk" >/dev/null; then echo "Unexpected SDK command: $sdk" >&2; exit 1; fi; done'
docker exec -u dev "$name" bash -lc '! curl -s --max-time 1 -o /dev/null http://127.0.0.1:8080/'
docker rm -f "$name" >/dev/null

docker run -d --name "$name" \
  -e SDK_PYTHON=3.13 -e SDK_NODE=22.x -e SDK_DOTNET=10 \
  -e SDK_JAVA=21 -e SDK_GO=1.24 -e SDK_RUST=1.85 \
  -e VSCODE_EDITOR_ENABLED=true -e PASSWORD=smoke-only-password \
  "$image" >/dev/null

ready=false
for _ in $(seq 1 180); do
  if docker logs "$name" 2>&1 | grep -q 'rust .* ready'; then ready=true; break; fi
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
docker logs "$name" 2>&1 | grep -q '^Removing incomplete node installation$'

docker rm -f "$name" >/dev/null
docker run -d --name "$name" "$image" >/dev/null
sleep 3
docker exec -u dev "$name" bash -lc 'for sdk in python python3 pip3 node npm npx corepack dotnet java javac go gofmt rustc cargo rustup; do ! command -v "$sdk" || exit 1; done'
