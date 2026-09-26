#!/usr/bin/env bash
set -euo pipefail

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT

cat > "$work/native" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1-}" == --version ]]; then
  echo 'codex-cli test'
  exit 0
fi

count=0
[[ ! -f "$FAKE_STATE" ]] || count=$(<"$FAKE_STATE")
count=$((count + 1))
printf '%s\n' "$count" > "$FAKE_STATE"

if [[ "${FAKE_MODE-}" == permanent ]]; then
  echo 'authentication failed' >&2
  exit 7
fi

if (( count == 1 )); then
  echo 'Error: app server did not become ready on /tmp/control.sock' >&2
  exit 1
fi

echo 'This machine is available for remote control.'
EOF
chmod 0755 "$work/native"

# Exercise the shipped wrapper with a fake native CLI that is slow once.
sed "s|^codex_bin=.*$|codex_bin=$work/native|" scripts/codex.sh > "$work/codex"
chmod 0755 "$work/codex"

FAKE_STATE="$work/state" "$work/codex" --version | grep -qx 'codex-cli test'
remote_state_file="$work/codex-home/.agent-devstation-remote-control-enabled"
mkdir -p "$work/codex-home"
output=$(CODEX_HOME="$work/codex-home" FAKE_STATE="$work/state" "$work/codex" remote-control start 2>"$work/stderr")
[[ "$output" == 'This machine is available for remote control.' ]]
[[ $(<"$work/state") == 2 ]]
[[ -f "$remote_state_file" ]]
grep -q 'retrying (1/2)' "$work/stderr"

CODEX_HOME="$work/codex-home" FAKE_STATE="$work/state" "$work/codex" remote-control stop >/dev/null
[[ ! -e "$remote_state_file" ]]

rm "$work/state"
status=0
CODEX_HOME="$work/codex-home" FAKE_STATE="$work/state" FAKE_MODE=permanent "$work/codex" remote-control start >"$work/stdout" 2>"$work/stderr" || status=$?
[[ "$status" == 7 ]]
[[ $(<"$work/state") == 1 ]]
[[ ! -e "$remote_state_file" ]]
grep -qx 'authentication failed' "$work/stderr"
! grep -q retrying "$work/stderr"

touch "$remote_state_file"
CODEX_HOME="$work/codex-home" FAKE_STATE="$work/state" "$work/codex" logout >/dev/null
[[ ! -e "$remote_state_file" ]]
