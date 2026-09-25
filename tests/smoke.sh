#!/usr/bin/env bash
set -euo pipefail

image=${IMAGE:-agent-devstation:ci}
name="devstation-smoke-$$"
trap 'docker rm -f "$name" >/dev/null 2>&1 || true' EXIT

docker run -d --name "$name" -e VSCODE_EDITOR_ENABLED=false "$image" >/dev/null
sleep 3
docker exec -u dev "$name" bash -lc 'codex --version && claude --version && code-server --version'
docker exec -u dev "$name" bash -lc 'for sdk in python python3 node dotnet java go rustc cargo; do if command -v "$sdk" >/dev/null; then echo "Unexpected SDK command: $sdk" >&2; exit 1; fi; done'
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
docker exec -u dev "$name" bash -lc 'curl -s -D - -o /dev/null http://127.0.0.1:8080/ | grep -qi "Location: ./login"'
docker exec -u dev "$name" bash -lc 'curl -s -c /tmp/editor-cookie -o /dev/null -d password=smoke-only-password http://127.0.0.1:8080/login; curl -s -b /tmp/editor-cookie -D - -o /dev/null http://127.0.0.1:8080/ | grep -qi "Location: ./?folder=/workspaces"'

before=$(docker logs "$name" 2>&1 | grep -c '^Installing ')
docker restart "$name" >/dev/null
sleep 5
after=$(docker logs "$name" 2>&1 | grep -c '^Installing ')
[[ "$before" == "$after" ]] || { echo 'Restart downloaded an SDK again' >&2; exit 1; }

docker rm -f "$name" >/dev/null
docker run -d --name "$name" "$image" >/dev/null
sleep 3
docker exec -u dev "$name" bash -lc 'for sdk in python python3 node dotnet java go rustc cargo; do ! command -v "$sdk" || exit 1; done'
