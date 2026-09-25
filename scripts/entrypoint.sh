#!/usr/bin/env bash
set -euo pipefail

case "${VSCODE_EDITOR_ENABLED:-false}" in
  true|false) ;;
  *) echo 'VSCODE_EDITOR_ENABLED must be true or false' >&2; exit 2 ;;
esac

if [[ "${VSCODE_EDITOR_ENABLED:-false}" == true && -z "${PASSWORD:-}" ]]; then
  echo 'EDITOR_PASSWORD (passed as PASSWORD) is required when the editor is enabled' >&2
  exit 2
fi

for value in "${DEV_UID:-1000}" "${DEV_GID:-1000}"; do
  [[ "$value" =~ ^[1-9][0-9]*$ ]] || { echo 'DEV_UID and DEV_GID must be positive integers' >&2; exit 2; }
done

if [[ "${DEV_GID:-1000}" != "$(id -g dev)" ]]; then groupmod -g "${DEV_GID:-1000}" dev; fi
if [[ "${DEV_UID:-1000}" != "$(id -u dev)" ]]; then usermod -u "${DEV_UID:-1000}" dev; fi
if [[ "$(stat -c %u:%g /home/dev)" != "$(id -u dev):$(id -g dev)" ]]; then
  chown -R dev:dev /home/dev
fi
if [[ "$(stat -c %u:%g /opt/codex)" != "$(id -u dev):$(id -g dev)" ]]; then
  chown -R dev:dev /opt/codex
fi

mkdir -p /home/dev/.codex /home/dev/.claude /home/dev/.local/share/code-server /workspaces
chown dev:dev /home/dev /home/dev/.codex /home/dev/.claude /home/dev/.local /home/dev/.local/share
chown -R dev:dev /home/dev/.local/share/code-server

# Installers run as root, but HOME belongs to dev in normal sessions. Keep
# installer caches out of the persisted dev home.
HOME=/root /usr/local/lib/agent-devstation/install-sdks.sh
if [[ "$(stat -c %u:%g /opt/sdk)" != "$(id -u dev):$(id -g dev)" ]]; then
  chown -R dev:dev /opt/sdk
fi
if [[ -d /home/dev/.cache && "$(stat -c %u:%g /home/dev/.cache)" != "$(id -u dev):$(id -g dev)" ]]; then
  chown -R dev:dev /home/dev/.cache
fi

if [[ $# -gt 0 ]]; then
  exec gosu dev "$@"
fi

if [[ "${VSCODE_EDITOR_ENABLED:-false}" == true ]]; then
  exec gosu dev code-server --bind-addr 0.0.0.0:8080 --auth password /workspaces
fi

exec gosu dev sleep infinity
