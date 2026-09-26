![Two luminous agents sharing a development workspace](assets/readme-banner.png)

# Agent Devstation

A prebuilt Docker workspace for **Codex**, **Claude Code**, GitHub CLI, and optional SDKs and browser editing. Projects live under `/workspaces`; the agents and editor share the same files and SDKs. Images support Linux AMD64 and ARM64. Neither setup needs a repository clone or image build.

## Simple setup: terminal agents

Use this for terminal work without changing host sandbox settings. Codex runs with full access **inside the container**; its phone Remote Control is unavailable in this setup.

1. Install Docker Engine with Compose. Copy [compose.yaml](compose.yaml) into a folder on your server and run `docker compose up -d`. The file pulls the prebuilt image and creates `workspaces/` beside it.
2. Sign in to the agent you want to use:

   ```sh
   docker compose exec -u dev agent-devstation codex login --device-auth
   docker compose exec -u dev agent-devstation claude auth login
   ```

3. Clone a project, then run either agent from it:

   ```sh
   docker compose exec -u dev agent-devstation git clone https://github.com/you/project.git /workspaces/project
   docker compose exec -u dev -w /workspaces/project agent-devstation codex --no-daemon --sandbox danger-full-access
   docker compose exec -u dev -w /workspaces/project agent-devstation claude
   ```

Run `docker compose exec -u dev agent-devstation bash` for a shell. The default Compose selects Python `3.14` and Node.js `24`; [change SDKs or enable the editor](#customize-either-setup) when needed. Claude Code phone Remote Control is also available with an eligible subscription; see the [full setup](#full-setup-editor-and-phone-remote-control).

## Full setup: editor and phone Remote Control

This enables the browser editor and Codex's Linux sandbox so you can try **both agents' official phone workflows**. Codex phone pairing in a headless container is experimental and depends on your ChatGPT account and phone UI. Claude Code requires an eligible subscription account; an API key alone cannot enable its Remote Control.

1. Install Docker Engine with Compose. Save this complete example as `compose.yaml` in a folder on your server. Choose SDK versions you need; empty values leave those SDKs off.

   ```yaml
   services:
     agent-devstation:
       image: ghcr.io/lucurlings/agent-devstation:latest
       hostname: agent-devspace
       pull_policy: always
       restart: unless-stopped
       init: true
       security_opt:
         - seccomp=unconfined
         - apparmor=unconfined
       environment:
         AGENT_DEVSTATION_SDK_PYTHON: "3.14"
         AGENT_DEVSTATION_SDK_NODE: "24"
         AGENT_DEVSTATION_SDK_DOTNET: ""
         AGENT_DEVSTATION_SDK_JAVA: ""
         AGENT_DEVSTATION_SDK_GO: ""
         AGENT_DEVSTATION_SDK_RUST: ""
         AGENT_DEVSTATION_VSCODE_EDITOR_ENABLED: "true"
         AGENT_DEVSTATION_VSCODE_PASSWORD: ${AGENT_DEVSTATION_VSCODE_PASSWORD:?Set it in .env}
         AGENT_DEVSTATION_UID: "1000"
         AGENT_DEVSTATION_GID: "1000"
       volumes:
         - ./workspaces:/workspaces
         - devstation-home:/home/dev
       ports:
         - "127.0.0.1:8080:8080"

   volumes:
     devstation-home:
   ```

2. In the same folder, create a local `.env` containing `AGENT_DEVSTATION_VSCODE_PASSWORD=your-long-unique-password`, replacing the example value with a unique password. Keep it private and out of Git. Run `docker compose up -d`; first startup downloads the selected SDKs and editor. The password opens the editor's own login page; it is separate from agent accounts.
3. Sign in to **both** agents with accounts eligible for their phone features, then add a project:

   ```sh
   docker compose exec -u dev agent-devstation codex login --device-auth
   docker compose exec -u dev agent-devstation claude auth login
   docker compose exec -u dev agent-devstation git clone https://github.com/you/project.git /workspaces/project
   ```

   If you use GitHub CLI, also run `docker compose exec -u dev agent-devstation gh auth login`.

4. Check the Codex sandbox:

   ```sh
   docker compose exec -u dev agent-devstation codex sandbox -c 'sandbox_mode="read-only"' /bin/sh -lc 'cd "$HOME" && pwd -P'
   ```

   It should print `/home/dev`. If it fails with a user-namespace error, follow the [host setup steps](docs/guide.md#codex-sandboxed-setup) and [OpenAI's Linux prerequisites](https://learn.chatgpt.com/docs/sandboxing?surface=cli#prerequisites). Ubuntu 24.04 may need a one-time AppArmor profile on the Docker host. The image includes `bubblewrap`. The two `security_opt` settings relax Docker's seccomp and container AppArmor filters for this service.

5. Start Codex Remote Control and pair the phone while signed in to the same ChatGPT account. Start Claude Code Remote Control from the project and open its URL or QR code; keep that command running while using it.

   ```sh
   docker compose exec -u dev agent-devstation codex remote-control start
   docker compose exec -u dev agent-devstation codex remote-control pair
   docker compose exec -u dev -w /workspaces/project agent-devstation claude remote-control
   ```

   Codex resumes a successful Remote Control start after container recreation; Claude's command must be run again. Neither agent needs a public inbound port. [Phone details and limitations](docs/guide.md#official-phone-remote-control).

6. Open the editor at `http://localhost:8080` **on the Docker host** and enter the `.env` password. From another machine, run `ssh -L 8080:127.0.0.1:8080 user@your-server` and open `http://localhost:8080` locally. Alternatively, use your own reverse proxy with TLS, authentication, and WebSocket support. A containerized proxy must share a Docker network with Agent Devstation and target **port 8080**. Only the editor uses that port; do not publish an agent protocol port. [Editor details](docs/guide.md#browser-editor).

Use `docker compose exec -u dev -w /workspaces/project agent-devstation codex` or the equivalent `claude` command for normal terminal sessions. You can move from the simple setup to this one without losing projects or logins if you keep the same mounts and volume name.

## Customize either setup

| Compose variable | Example |
| --- | --- |
| `AGENT_DEVSTATION_SDK_PYTHON` | `3.14` |
| `AGENT_DEVSTATION_SDK_NODE` | `24` |
| `AGENT_DEVSTATION_SDK_DOTNET` | `10` |
| `AGENT_DEVSTATION_SDK_JAVA` | `21` |
| `AGENT_DEVSTATION_SDK_GO` | `1.26` |
| `AGENT_DEVSTATION_SDK_RUST` | `1.85` |

Set versions in Compose (or use an ignored `.env` with the linked default Compose file). An empty value disables an SDK. A partial number selects the latest matching release at install time; an exact number such as `24.0.1` pins it. `.x` is not accepted. After editing Compose, run `docker compose up -d`: Compose recreates the container and startup installs selected SDKs and removes unselected ones. A normal restart reuses installed versions. [SDK details](docs/guide.md#sdk-selection).

The linked Compose file leaves the editor off. To enable it there, set `AGENT_DEVSTATION_VSCODE_EDITOR_ENABLED=true`, set `AGENT_DEVSTATION_VSCODE_PASSWORD` in `.env`, and uncomment its loopback port mapping. Disabling it removes its installation. On Linux, set `AGENT_DEVSTATION_UID` and `AGENT_DEVSTATION_GID` to match your project files if they are not owned by `1000:1000`.

[Codex and Claude API-key login](docs/guide.md#authentication) is available for terminal use. Codex phone pairing requires ChatGPT sign-in; Claude phone control requires subscription sign-in. Credentials live in the home volume, never in the image.

## Updates and security

`latest` follows full releases; `nightly` follows successful merges to `main`. Run `docker compose up -d` to pull updates. Replace your copied Compose file when its settings change. Back up `workspaces/` and the named home volume; `docker compose down -v` deletes that volume. Do not mount the Docker socket or expose the editor without authentication. [Troubleshooting](docs/guide.md#updates-troubleshooting-and-security).

Original project code is [Apache 2.0 licensed](LICENSE). See [Contributing](CONTRIBUTING.md), [Security](SECURITY.md), the [Code of Conduct](CODE_OF_CONDUCT.md), and [repository settings](docs/repository-settings.md).

<a href="https://www.star-history.com/?repos=LucUrlings%2Fagent-devstation&type=date"><img alt="Agent Devstation star history" src="https://api.star-history.com/chart?repos=LucUrlings/agent-devstation&type=date" /></a>
