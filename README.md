![Two luminous agents sharing a development workspace](assets/readme-banner.png)

# Agent Devstation

A ready-to-run Docker workspace with **Codex**, **Claude Code**, and **GitHub CLI**. Add projects under `/workspaces`; both agents and the optional browser editor see the same files and selected SDKs. Prebuilt images support Linux AMD64 and ARM64. You never need to build one.

## Choose a setup

| Feature | Simple | Full |
| --- | --- | --- |
| Codex | Terminal CLI with full access inside the container | Normal Codex sandbox and background server |
| Extra host setup | None | May need user-namespace setup |
| Phone Remote Control | Claude Code only | Claude Code and Codex, subject to account availability |

Both use the same image and [compose.yaml](compose.yaml). No clone or image build is needed.

## Install (both setups)

1. Install Docker Engine with Compose, then copy [compose.yaml](compose.yaml) to a folder on your server. For the **full** setup, uncomment its three `security_opt` lines before starting.
2. Run `docker compose up -d` in that folder. Compose pulls the prebuilt image.
3. Sign in to either or both agents:

   ```sh
   docker compose exec -u dev agent-devstation codex login --device-auth
   docker compose exec -u dev agent-devstation claude auth login
   ```

   Use only the login you need. [API-key login options](docs/guide.md#authentication) are also available; login state persists in the home volume.

4. Add a project (or use one already under `/workspaces`). Compose creates the local `workspaces/` folder automatically:

   ```sh
   docker compose exec -u dev agent-devstation git clone https://github.com/you/project.git /workspaces/project
   ```

For a shell, run `docker compose exec -u dev agent-devstation bash`.

## Simple setup: terminal agents

Use the unchanged Compose file. Run either agent from a project:

```sh
docker compose exec -u dev -w /workspaces/project agent-devstation codex --no-daemon --sandbox danger-full-access
docker compose exec -u dev -w /workspaces/project agent-devstation claude
```

`--no-daemon` avoids host namespace setup but disables **Codex** phone Remote Control. `danger-full-access` gives Codex full access as `dev` inside the container, including saved logins. Docker still controls host mounts. [OpenAI's permissions guide](https://learn.chatgpt.com/docs/sandboxing?surface=cli#how-permissions-work).

## Full setup: sandbox and phone

After enabling `security_opt` in step 1, check Codex's sandbox:

```sh
docker compose exec -u dev agent-devstation codex sandbox -c 'sandbox_mode="read-only"' /bin/sh -lc 'cd "$HOME" && pwd -P'
```

It should print `/home/dev`. If it fails, follow the [host instructions](docs/guide.md#codex-sandboxed-setup) and [OpenAI's prerequisites](https://learn.chatgpt.com/docs/sandboxing?surface=cli#prerequisites); Ubuntu 24.04 may need a one-time AppArmor profile **on the host**. The image includes `bubblewrap`. The Compose options disable Docker's seccomp and container AppArmor filters for this service.

Run normal Codex from your project:

```sh
docker compose exec -u dev -w /workspaces/project agent-devstation codex
```

For phone control, start its background server in another shell, then pair:

```sh
docker compose exec -u dev agent-devstation codex remote-control start
docker compose exec -u dev agent-devstation codex remote-control pair
```

Headless Codex pairing is experimental and depends on your ChatGPT account and phone UI. [Phone setup and limitations](docs/guide.md#official-phone-remote-control). Claude Code works as shown in the simple setup. Switching setups later keeps projects and logins; run `docker compose up -d` to apply the Compose change.

## SDKs and editor (either setup)

The [included Compose file](compose.yaml) is the complete example. It selects Python `3.14` and Node.js `24`; other SDKs and the editor are off. Put overrides in an ignored `.env` beside Compose:

| Variable | Example |
| --- | --- |
| `AGENT_DEVSTATION_SDK_PYTHON` | `3.14` (default) |
| `AGENT_DEVSTATION_SDK_NODE` | `24` (default) |
| `AGENT_DEVSTATION_SDK_DOTNET` | `10` |
| `AGENT_DEVSTATION_SDK_JAVA` | `21` |
| `AGENT_DEVSTATION_SDK_GO` | `1.26` |
| `AGENT_DEVSTATION_SDK_RUST` | `1.85` |

An empty value disables an SDK, including either default. A partial version selects the latest matching release at install time; an exact version such as `24.0.1` pins it. `.x` is not accepted. Run `docker compose up -d` after changing settings: Compose recreates the container, then startup installs exactly the selected SDKs. A normal restart reuses installed SDKs. [Version details and troubleshooting](docs/guide.md#sdk-selection).

Set `AGENT_DEVSTATION_VSCODE_EDITOR_ENABLED=true` and `AGENT_DEVSTATION_VSCODE_PASSWORD` to enable code-server on **container port 8080**. Uncomment the loopback port mapping in Compose for local browser access. For remote access, use your own reverse proxy with TLS and authentication. The editor shares `/workspaces` and the SDKs; disabling it removes its installation. [Editor setup](docs/guide.md#browser-editor).

On Linux, set `AGENT_DEVSTATION_UID` and `AGENT_DEVSTATION_GID` if project files are not owned by `1000:1000`. The default Compose keeps Docker's security filters.

## Phone Remote Control

Claude Code phone control works from either setup: run `docker compose exec -u dev -w /workspaces/project agent-devstation claude remote-control`. It needs an eligible Claude subscription login, not an API key alone. Codex uses the full setup above. Both use outbound connections; neither needs a public agent port. [Details](docs/guide.md#official-phone-remote-control).

## Updates and security

`latest` follows full releases; `nightly` follows successful merges to `main`. Run `docker compose up -d` to update the image; replace your copied Compose file when its settings change. If Compose from `main` is newer than the full release, set `AGENT_DEVSTATION_TAG=nightly` in `.env` after its image publishes. The home volume keeps logins across recreation; back it up with `workspaces/`. Avoid `docker compose down -v` unless you intend to delete that volume. Do not mount the Docker socket or expose the editor without authentication. [Updates and troubleshooting](docs/guide.md#updates-troubleshooting-and-security).

Original project code is [Apache 2.0 licensed](LICENSE). See [Contributing](CONTRIBUTING.md), [Security](SECURITY.md), the [Code of Conduct](CODE_OF_CONDUCT.md), and [repository settings](docs/repository-settings.md).

<a href="https://www.star-history.com/?repos=LucUrlings%2Fagent-devstation&type=date"><img alt="Agent Devstation star history" src="https://api.star-history.com/chart?repos=LucUrlings/agent-devstation&type=date" /></a>
