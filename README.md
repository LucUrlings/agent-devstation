![Two luminous agents sharing a development workspace](assets/readme-banner.png)

# Agent Devstation

A ready-to-run Docker workspace with **Codex**, **Claude Code**, and **GitHub CLI**. Add projects under `/workspaces`; both agents and the optional browser editor see the same files and selected SDKs. Prebuilt images support Linux AMD64 and ARM64. You never need to build one.

## Quick start

1. Install Docker with Compose. Copy [compose.yaml](compose.yaml) into a directory on your server; it is the only setup file.
2. Start the prebuilt image; Compose pulls it automatically and does not build it:

   ```sh
   docker compose up -d
   ```

3. Sign in to either or both agents:

   ```sh
   docker compose exec -u dev agent-devstation codex login --device-auth
   docker compose exec -u dev agent-devstation claude auth login
   ```

4. Add a project and run an agent from it:

   ```sh
   docker compose exec -u dev agent-devstation git clone https://github.com/you/project.git /workspaces/project
   docker compose exec -u dev -w /workspaces/project agent-devstation codex --no-daemon --sandbox danger-full-access
   docker compose exec -u dev -w /workspaces/project agent-devstation claude
   ```

Use `docker compose exec -u dev agent-devstation bash` for a shell. [Authentication options](docs/guide.md#authentication) include ChatGPT or an OpenAI API key for Codex, and a Claude subscription or Anthropic API key for Claude Code. Agent login state persists in the named `/home/dev` volume; projects live in the `./workspaces` bind mount.

The Codex command gives it full access **inside the container** and skips phone Remote Control. For Codex's normal sandbox and phone access, see the [sandboxed setup](docs/guide.md#codex-sandboxed-setup) and [OpenAI's permissions guide](https://learn.chatgpt.com/docs/sandboxing?surface=cli#how-permissions-work).

## Configure

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

On Linux, set `AGENT_DEVSTATION_UID` and `AGENT_DEVSTATION_GID` if project files are not owned by `1000:1000`. The image includes `bubblewrap` for the optional sandboxed path. The default Compose keeps Docker's security filters.

## Phone Remote Control

Neither agent needs a public port for its official phone Remote Control. Codex needs the [sandboxed setup](docs/guide.md#codex-sandboxed-setup) and ChatGPT login; headless pairing remains experimental. Claude Code needs an eligible subscription login, not just an API key. See [commands and limitations](docs/guide.md#official-phone-remote-control).

## Updates and security

`latest` follows full releases; `nightly` follows successful merges to `main`. Run `docker compose up -d` to update the image; replace your copied Compose file when its settings change. If Compose from `main` is newer than the full release, set `AGENT_DEVSTATION_TAG=nightly` in `.env` after its image publishes. The home volume keeps logins across recreation; back it up with `workspaces/`. Avoid `docker compose down -v` unless you intend to delete that volume. Do not mount the Docker socket or expose the editor without authentication. [Updates and troubleshooting](docs/guide.md#updates-troubleshooting-and-security).

Original project code is [Apache 2.0 licensed](LICENSE). See [Contributing](CONTRIBUTING.md), [Security](SECURITY.md), the [Code of Conduct](CODE_OF_CONDUCT.md), and [repository settings](docs/repository-settings.md).

<a href="https://www.star-history.com/?repos=LucUrlings%2Fagent-devstation&type=date"><img alt="Agent Devstation star history" src="https://api.star-history.com/chart?repos=LucUrlings/agent-devstation&type=date" /></a>
