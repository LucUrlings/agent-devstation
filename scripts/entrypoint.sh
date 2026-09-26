#!/usr/bin/env bash
set -euo pipefail

editor_enabled=${AGENT_DEVSTATION_VSCODE_EDITOR_ENABLED-${VSCODE_EDITOR_ENABLED-false}}
editor_password=${AGENT_DEVSTATION_VSCODE_PASSWORD-${VSCODE_PASSWORD-${PASSWORD-}}}
dev_uid=${AGENT_DEVSTATION_UID-${DEV_UID-1000}}
dev_gid=${AGENT_DEVSTATION_GID-${DEV_GID-1000}}

case "$editor_enabled" in
  true|false) ;;
  *) echo 'AGENT_DEVSTATION_VSCODE_EDITOR_ENABLED must be true or false' >&2; exit 2 ;;
esac

if [[ "$editor_enabled" == true && -z "$editor_password" ]]; then
  echo 'AGENT_DEVSTATION_VSCODE_PASSWORD is required when the editor is enabled' >&2
  exit 2
fi

for value in "$dev_uid" "$dev_gid"; do
  [[ "$value" =~ ^[1-9][0-9]*$ ]] || { echo 'AGENT_DEVSTATION_UID and AGENT_DEVSTATION_GID must be positive integers' >&2; exit 2; }
done

if [[ "$dev_gid" != "$(id -g dev)" ]]; then groupmod -g "$dev_gid" dev; fi
if [[ "$dev_uid" != "$(id -u dev)" ]]; then usermod -u "$dev_uid" dev; fi
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

if [[ "$editor_enabled" == true ]]; then
  # code-server uses PASSWORD internally; users configure the namespaced setting.
  exec gosu dev env PASSWORD="$editor_password" code-server --bind-addr 0.0.0.0:8080 --auth password /workspaces
fi

exec gosu dev sleep infinity
