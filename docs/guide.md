# Agent Devstation guide

Start with the [README](../README.md) and copy the complete [compose.yaml](../compose.yaml). The image is prebuilt; no repository clone or local build is needed.

## Image tags and releases

| Tag | Use |
| --- | --- |
| `latest` | Latest full release; Compose default. |
| `v0.1.0` | Example fixed release. |
| `nightly` | Latest successful build from `main`. |
| `nightly-<commit SHA>` | One tested `main` commit. |

Set `AGENT_DEVSTATION_TAG=nightly` in an optional `.env` to use a new merged change before the next release. `pull_policy: always` checks GHCR on every `docker compose up -d`. Release tags promote an already tested `main` image; they do not rebuild it. If an anonymous pull is denied, the GHCR package may need its visibility set to **Public**.

## Compose and projects

The linked [compose.yaml](../compose.yaml) is the complete one-file example. It mounts host `./workspaces` at `/home/dev/workspaces` inside the container and a named volume at `/home/dev` for logins and settings. This puts projects under the phone folder picker's starting home folder. Both agents and the optional editor see the same files and SDKs. `hostname` makes the shell prompt show `dev@agent-devspace`, while `container_name` names the Docker container `agent-devspace`. The Compose service remains `agent-devstation` for `docker compose exec`. A fixed container name allows only one instance with that name per Docker host; change or remove it for another instance. Do not use `docker compose down -v` unless you want to delete the home volume.

`init: true` forwards stop signals and reaps child processes. `stdin_open` and `tty` are unnecessary because `docker compose exec` provides a terminal. On Linux, set `AGENT_DEVSTATION_UID` and `AGENT_DEVSTATION_GID` to the owner of your project files if they differ from `1000:1000`. The image repairs an empty root-owned `./workspaces` bind mount; it will not change a nonempty project's ownership. The container does not mount the Docker socket or use `privileged: true`.

### Simple Codex CLI

Run Codex without host namespace setup:

```sh
docker compose exec -u dev -w /home/dev/workspaces/project agent-devstation codex --no-daemon --sandbox danger-full-access
```

Replace `project` with your project directory. Codex can access all files available to `dev` inside the container, including saved logins. `--no-daemon` means no Codex phone Remote Control. See [OpenAI's permission modes](https://learn.chatgpt.com/docs/sandboxing?surface=cli#how-permissions-work).

### Codex sandboxed setup

For Codex's normal sandbox and phone Remote Control, uncomment `security_opt` in `compose.yaml` and run `docker compose up -d`. Those options disable Docker's seccomp and container AppArmor filters for this service. The image includes `bubblewrap`; check whether your Docker host permits its sandbox:

```sh
docker compose exec -u dev agent-devstation codex sandbox -c 'sandbox_mode="read-only"' /bin/sh -lc 'cd "$HOME" && pwd -P'
```

If it prints `/home/dev`, the sandbox prerequisite is ready. Run plain `codex` from a project, or sign in with ChatGPT and follow the [Codex Remote Control steps](#official-phone-remote-control) to start and pair your phone.

### bwrap loopback error

If the sandbox check prints this error on an **Ubuntu 24.04 Docker host**:

```text
bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted
```

First confirm that the full Compose example's `security_opt` lines are enabled and run `docker compose up -d` to recreate the container. Then copy and load Ubuntu's `bwrap` AppArmor profile **on the Docker host**:

```sh
sudo apt update
sudo apt install apparmor-profiles apparmor-utils
sudo install -m 0644 /usr/share/apparmor/extra-profiles/bwrap-userns-restrict /etc/apparmor.d/bwrap-userns-restrict
sudo apparmor_parser -r /etc/apparmor.d/bwrap-userns-restrict
```

Run the sandbox check again; it should print `/home/dev`. The package step may report both packages already installed—still run the copy and parser commands. On Ubuntu 26.04, the profile ships with `apparmor` at `/etc/apparmor.d/bwrap-userns-restrict`; load it there if needed. Debian and Fedora may use different host rules. [OpenAI's Linux prerequisites](https://learn.chatgpt.com/docs/sandboxing?surface=cli#prerequisites) explain the host requirements. The image cannot override a host namespace restriction.

To undo these Ubuntu 24.04 profile steps **if that profile file did not exist before you copied it**, remove the loaded profile first, then the file:

```sh
sudo apparmor_parser -R /etc/apparmor.d/bwrap-userns-restrict
sudo rm /etc/apparmor.d/bwrap-userns-restrict
```

`apt update` needs no rollback. Remove `apparmor-profiles` and `apparmor-utils` with `sudo apt remove apparmor-profiles apparmor-utils` only if you installed them solely for this and do not use them elsewhere. Removing the profile can make Codex's sandbox fail again on that host.

## SDK selection

Compose defaults to Python `3.14` and Node.js `24`; .NET, Java, Go, and Rust are off. Set the `AGENT_DEVSTATION_SDK_*` variables in an optional ignored `.env` beside Compose. An empty value turns that SDK off. An unset variable when running the image directly selects none.

Use numbers only: `24` follows the latest Node 24 release, `3.13` follows Python 3.13 patches, and `24.0.1` pins that exact Node release. `.x` is not accepted. Java also supports four-part versions; Rust `1` follows its stable channel. An unavailable version fails startup.

Run `docker compose up -d` after changing a selection. Compose recreates the container, then startup installs the selected SDKs under `/opt/sdk` and removes unselected ones. A normal restart reuses them. Startup logs say what was installed, reused, or removed. SDK commands and variables such as `JAVA_HOME` and `DOTNET_ROOT` work in agent shells and the editor terminal. Codex, Claude Code, and GitHub CLI are included independently of SDK choices.

## Authentication

**Codex with ChatGPT:** `docker compose exec -u dev agent-devstation codex login --device-auth`. Enable device-code login in ChatGPT settings if needed. For API-key login, export `OPENAI_API_KEY` on the host and pipe it without saving it in Compose:

```sh
printenv OPENAI_API_KEY | docker compose exec -T -u dev agent-devstation codex login --with-api-key
```

Codex stores login state in the home volume. API-key login does not provide a ChatGPT identity for phone pairing. [OpenAI authentication](https://learn.chatgpt.com/docs/auth).

**Claude Code:** run `docker compose exec -u dev agent-devstation claude auth login` for a subscription account. For API-key use, export `ANTHROPIC_API_KEY` on the host and run `docker compose exec -u dev -e ANTHROPIC_API_KEY agent-devstation claude`. [Claude authentication](https://code.claude.com/docs/en/authentication).

**GitHub CLI:** run `docker compose exec -u dev agent-devstation gh auth login`. Its token may be saved as plain text under `/home/dev/.config/gh`; use a temporary `GH_TOKEN` instead if preferred. [GitHub CLI authentication](https://cli.github.com/manual/gh_auth_login).

Keep keys and login files out of the image, repository, and `.env`. Anyone with access to the home volume or editor terminal can read them.

## Official phone Remote Control

Neither agent needs a public agent port. Both workflows use outbound connections.

**Codex:** complete the [sandboxed setup](#codex-sandboxed-setup), sign in with ChatGPT, then run:

```sh
docker compose exec -u dev agent-devstation codex remote-control start
docker compose exec -u dev agent-devstation codex remote-control pair
```

[OpenAI documents these CLI commands](https://learn.chatgpt.com/docs/developer-commands) but marks them experimental. Its [general phone setup guide](https://learn.chatgpt.com/docs/remote-connections) still describes pairing through the desktop app, so headless pairing is not guaranteed. If your phone offers manual code entry, use the short-lived code while signed in to the same ChatGPT account. An API key alone cannot pair a phone. Do not expose a Codex app-server port.

After a successful `start`, the home volume remembers the choice and resumes Remote Control after restart or recreation. `codex remote-control stop` or `codex logout` turns off automatic resumption. A recreated container downloads Codex's separate daemon package again. The phone folder picker starts at `/home/dev` and should show `workspaces` there; if it cannot find the home folder, repeat the [sandbox probe](#codex-sandboxed-setup). Pairing and the phone UI require a manual account test.

**Claude Code:** from a project, run `docker compose exec -u dev -w /home/dev/workspaces/project agent-devstation claude remote-control`, then open its URL or scan its QR code. Claude requires an eligible Pro, Max, Team, or Enterprise subscription login; an API key alone does not enable Remote Control. Organization policy and project trust can also block it. Re-run the command after a container restart. [Claude Remote Control](https://code.claude.com/docs/en/remote-control).

## Browser editor

Set `AGENT_DEVSTATION_VSCODE_EDITOR_ENABLED=true` and a strong `AGENT_DEVSTATION_VSCODE_PASSWORD` in `.env`, then run `docker compose up -d`. The image downloads code-server on first use; turning the editor off and recreating removes it. Its login page is separate from agent accounts. It opens `/home/dev/workspaces` and its terminal has the selected SDKs.

Container port **8080** serves only the editor. For local access, uncomment the loopback port mapping in Compose. For remote access, configure your reverse proxy to reach `agent-devstation:8080` on a shared network, with TLS, proxy authentication, and WebSocket support. Keep code-server's own password enabled. Do not expose an agent protocol port or mount the Docker socket.

## Updates, troubleshooting, and security

Run `docker compose up -d` to pull the selected tag. A new image or changed environment recreates the container and reinstalls selected SDKs and editor. `docker compose restart` keeps the existing container and does not apply changed SDK selections. Back up both `workspaces/` and the named home volume; `docker compose down -v` deletes the volume.

If startup fails, check `docker compose logs agent-devstation` for version, download, or workspace ownership errors. For a Codex daemon socket error, inspect `/home/dev/.codex/app-server-daemon/daemon.stderr.log` inside the container; the socket message alone does not identify the cause. If you upgraded from the old `devstation` service name, run `docker compose up -d --remove-orphans`.

The editor and agents can read mounted projects and home credentials and reach the network. Use trusted projects, keep the editor authenticated, and never mount the Docker socket. See [SECURITY.md](../SECURITY.md) for private vulnerability reporting.
