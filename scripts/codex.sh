#!/usr/bin/env bash
set -euo pipefail

codex_bin=/opt/codex/packages/standalone/current/bin/codex

# Codex can launch its on-demand daemon but exhaust its socket-readiness wait
# on a slow first start. Retry only that command and only for that error.
if [[ "${1-}" != remote-control || "${2-}" != start ]]; then
  exec "$codex_bin" "$@"
fi

stdout_file=$(mktemp)
stderr_file=$(mktemp)
trap 'rm -f -- "$stdout_file" "$stderr_file"' EXIT

for attempt in 1 2 3; do
  if "$codex_bin" "$@" >"$stdout_file" 2>"$stderr_file"; then
    cat "$stdout_file"
    cat "$stderr_file" >&2
    exit 0
  else
    status=$?
  fi

  if (( attempt == 3 )) || ! grep -q 'app server did not become ready on' "$stdout_file" "$stderr_file"; then
    cat "$stdout_file"
    cat "$stderr_file" >&2
    exit "$status"
  fi

  echo "Codex daemon is still starting; retrying ($attempt/2)..." >&2
  sleep 2
done
