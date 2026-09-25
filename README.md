![Two luminous agents sharing a development workspace](assets/readme-banner.png)

# Agent Devstation

A ready-to-run Docker development station for multiple projects. The Linux image includes **Codex**, **Claude Code**, and an optional browser editor (code-server). Select Python, Node.js, .NET, Java, Go, and Rust SDK versions through Compose. All tools see the same `/workspaces` tree and global SDK paths.

The publishing workflows build `linux/amd64` and `linux/arm64` images at `ghcr.io/lucurlings/agent-devstation`. Merges to `main` publish `nightly-latest`; full GitHub releases publish `latest` and a version tag. Users only pull images—no local build is part of setup.

## Quick start

1. Install Docker Engine or Docker Desktop with Compose.
2. Download [`compose.yaml`](compose.yaml) and [`sample.env`](sample.env) into one directory. Rename `sample.env` to `.env` and edit SDK versions.
3. Start the latest full release:

   ```sh
   mkdir -p workspaces
   docker compose pull
   docker compose up -d
   docker compose logs -f devstation
   ```

4. Put repositories in `workspaces/`, for example `git clone https://github.com/you/project.git workspaces/project`. Run either agent from a project:

   ```sh
   docker compose exec -u dev -w /workspaces/project devstation codex
   docker compose exec -u dev -w /workspaces/project devstation claude
   ```

There is no agent selector in Compose. Use `docker compose exec -u dev devstation bash` for a shell. Each project is a directory under the one mounted `workspaces/` tree.

## Image tags and releases

| Tag | Meaning |
| --- | --- |
| `latest` | Newest full release; Compose default. |
| `v0.1.0` (example) | A fixed full release. |
| `nightly-latest` | Newest successful merge to `main`; opt in with `DEVSTATION_TAG=nightly-latest`. |
| `nightly-<commit SHA>` | The exact image from a `main` commit. |

After CI passes for a push to `main`, the `Publish nightly image` workflow builds both architectures in parallel and publishes the nightly tags only after both builds succeed. The publishing workflow checks that the successful CI run came from this repository's `main` push and builds its exact commit; fork pull requests cannot trigger a publish job. The separate `Publish release image` workflow runs when a full GitHub release is published. Its tag, such as `v0.1.0`, must point to a commit on `main`; it promotes that commit's already built multi-platform image to the version tag and `latest` without rebuilding. Wait for the nightly workflow on `main` to finish before creating the release. `latest` does not move on ordinary merges.

The first GHCR package may need its visibility changed to **Public** before anonymous `docker compose pull` works. After the first nightly publish, open your GitHub profile's **Packages → agent-devstation → Package settings → Change visibility**, then test an unauthenticated pull. Public image access does not grant access to agent logins or project files.

## Complete Compose configuration

The included [`compose.yaml`](compose.yaml) has **no `build:` instruction**. It mounts `./workspaces` for project files and a Docker named volume for `/home/dev`, including both agents' login state and editor settings. The editor is disabled by default.

```yaml
services:
  devstation:
    image: ghcr.io/lucurlings/agent-devstation:${DEVSTATION_TAG:-latest}
    init: true
    stdin_open: true
    tty: true
    environment:
      SDK_PYTHON: ${SDK_PYTHON-}
      SDK_NODE: ${SDK_NODE-}
      SDK_DOTNET: ${SDK_DOTNET-}
      SDK_JAVA: ${SDK_JAVA-}
      SDK_GO: ${SDK_GO-}
      SDK_RUST: ${SDK_RUST-}
      VSCODE_EDITOR_ENABLED: ${VSCODE_EDITOR_ENABLED-false}
      PASSWORD: ${EDITOR_PASSWORD-}
      DEV_UID: ${DEV_UID-1000}
      DEV_GID: ${DEV_GID-1000}
    volumes:
      - ./workspaces:/workspaces
      - devstation-home:/home/dev
    restart: unless-stopped
volumes:
  devstation-home:
```

The `dev` account defaults to UID/GID 1000. On Linux, set `DEV_UID` and `DEV_GID` in `.env` to the output of `id -u` and `id -g` if your bind-mounted projects use different ownership. Docker Desktop handles its usual bind mount mapping. These values identify a user, not a process ID; no PID setting is needed. The container starts as root to install system SDKs, then runs the editor and idle process as `dev`; agent examples explicitly use `-u dev`. It never mounts the Docker socket.

## SDK selection

Set any of these in `.env`; leave others empty or remove them. Values are numeric versions with one to three components and optional `.x`, except Java, which accepts a major version only. Partial versions pick the latest matching patch **when installed**. Pin the full version for reproducibility where the upstream installer supports it.

| Variable | Example | Commands |
| --- | --- | --- |
| `SDK_PYTHON` | `3.13` | `python`, `python3`, `pip3` |
| `SDK_NODE` | `22.x` | `node`, `npm`, `npx`, `corepack` |
| `SDK_DOTNET` | `10` | `dotnet` |
| `SDK_JAVA` | `21` | `java`, `javac` |
| `SDK_GO` | `1.24` | `go`, `gofmt` |
| `SDK_RUST` | `1.85` | `rustc`, `cargo`, `rustup` |

Startup validates all values before downloads, checks installed versions, and installs only missing selections into `/opt/sdk/<language>/`. If a download or extraction was interrupted, the next start removes the incomplete `current` installation and retries. The image `PATH` includes stable `current` links there. `DOTNET_ROOT`, `JAVA_HOME`, `GOROOT`, `GOPATH`, `CARGO_HOME`, and `RUSTUP_HOME` are fixed in the image environment. Thus commands and required variables are available to agents, Compose shells, and the editor terminal. Codex, Claude Code, and code-server have separate dependencies; code-server's bundled Node is not on the user `PATH`. The startup script does not claim an SDK absent just because it was unselected; CI checks the actual commands.

Changing an SDK variable changes Compose configuration. Run `docker compose up -d` to **recreate** the container. This discards its writable SDK layer, so exactly the new selection is installed. `docker compose restart` retains the container and skips downloads, but does not apply changed configuration. `docker compose down` removes the container but preserves the home volume and bind-mounted projects; avoid `down -v` unless you mean to delete login state. A recreated container downloads selected SDKs again; no SDK volume retains a deselected runtime.

First installation needs outbound HTTPS. Python uses Astral uv managed distributions; Node.js comes from nodejs.org; .NET from Microsoft; Java from Eclipse Temurin; Go from go.dev; Rust from rustup. An unavailable version fails startup rather than silently selecting another major. Java selects the latest Temurin patch for the requested major, so use a major such as `21`.

## Authentication

**Codex with ChatGPT:** run `docker compose exec -u dev devstation codex login --device-auth`. Enable device code login in ChatGPT security settings, or have a workspace admin enable it, then open the printed URL and enter the one-time code. `codex login` also supports the browser flow when its callback is reachable. [OpenAI Docs: Codex authentication](https://learn.chatgpt.com/docs/auth)

**Codex with an API key:** set `OPENAI_API_KEY` in your host shell and pipe it to the official login command, without placing the key in Compose:

```sh
printenv OPENAI_API_KEY | docker compose exec -T -u dev devstation codex login --with-api-key
docker compose exec -u dev devstation codex login status
```

Codex stores credentials under `/home/dev/.codex` on the named home volume. API key usage is billed through OpenAI Platform and some ChatGPT features are unavailable. [OpenAI Docs: API key login](https://learn.chatgpt.com/docs/auth)

**Claude Code with a subscription:** run `docker compose exec -u dev devstation claude auth login`, select the claude.ai account flow, and complete the browser instructions. Its login and settings files are in the named home volume. **Claude Code with an API key:** export `ANTHROPIC_API_KEY` on the host, then run `docker compose exec -u dev -e ANTHROPIC_API_KEY devstation claude`. Interactive Claude may ask once before using the key; `claude -p` uses it when present. Unset the variable for subscription use. [Claude Code authentication](https://code.claude.com/docs/en/authentication)

Never put agent API keys in the image, repository, `.env`, or command history. The ignored `.env` holds SDK choices and, if enabled, the editor password; protect it as a secret. Anyone with Docker daemon, home volume, editor terminal, or agent account access can read sensitive project and login data.

## Official phone Remote Control

Both workflows use outbound connections. This project does not publish an agent HTTP endpoint or expose a Codex app server.

**Codex:** sign in with ChatGPT first, then run:

```sh
docker compose exec -u dev devstation codex remote-control start
docker compose exec -u dev devstation codex remote-control pair
```

OpenAI's [developer command reference](https://learn.chatgpt.com/docs/developer-commands) documents `start` and the short-lived manual code from `pair`, but marks the CLI command **experimental**. If your ChatGPT mobile Remote UI offers manual code entry for your account, use that code while signed in to the same account and workspace. The separate [Remote connections setup guide](https://learn.chatgpt.com/docs/remote-connections) currently says initial mobile pairing requires the ChatGPT desktop app on macOS or Windows and cannot be set up from the CLI or IDE. Therefore headless Docker phone pairing is **not guaranteed** by the general setup guide and needs an account-based test. If manual pairing is unavailable, use the documented desktop-app QR flow on a supported host; this container alone cannot replace that host. Do not publish a Codex app-server port as a workaround.

`codex remote-control` runs in the foreground instead of `start`; `codex remote-control stop` stops the managed service. It uses an outbound connection and a local daemon, not a public WebSocket listener. ChatGPT authentication, outbound access, account/workspace permissions, and mobile feature availability are required; API-key login alone lacks the ChatGPT identity for pairing. [OpenAI Docs: Remote on a phone](https://developers.openai.com/blog/mastering-codex-remote-for-engineering)

After a container restart or recreation, run `codex remote-control start` again; the image does not start Remote Control until you choose to. Your ChatGPT login remains in the home volume.

**Claude Code:** from a trusted project, run `docker compose exec -u dev -w /workspaces/project devstation claude remote-control` for server mode, or `claude --remote-control` for an interactive session. Accept the one-time confirmation; open its session URL on your phone or scan its QR code in the Claude app. `/remote-control` in an existing session enables it there. Claude requires a claude.ai **Pro, Max, Team, or Enterprise** subscription login. Team and Enterprise owners must enable the organization setting. API keys, `ANTHROPIC_AUTH_TOKEN`, and limited setup tokens cannot enable it. Accept workspace trust in the project first. The host must remain running with outbound HTTPS. [Claude Code Remote Control](https://code.claude.com/docs/en/remote-control)

Claude's Remote Control process also stops when the container stops. Re-run it from the project after a restart; saved Claude login state remains in the home volume.

Phone pairing requires your accounts and phone, so CI cannot complete it. Remote sessions may send source and transcript content to the provider under its terms; review your provider account and data settings.

## Browser editor

Set `VSCODE_EDITOR_ENABLED=true` and a strong `EDITOR_PASSWORD` in the ignored `.env`. For **local access**, uncomment the loopback port mapping in `compose.yaml`, run `docker compose up -d`, and open `http://127.0.0.1:8080`. code-server opens `/workspaces`, and its integrated terminal has the selected SDKs. Startup rejects an enabled editor without a password. Its service port is **8080**.

For remote access, connect your own reverse proxy to the editor on **container port 8080**. If the proxy runs in the same Compose project, attach it to a shared private network and forward to `http://devstation:8080`; otherwise publish the editor port only to an address the proxy can reach. Configure TLS, proxy authentication, WebSocket upgrades, and forwarded host/protocol headers in your proxy. Keep code-server's password enabled as a second gate. Do not publish an agent protocol endpoint or mount the Docker socket into this container. The editor is a powerful shell into projects and saved logins; grant access only to trusted operators.

## Updates, troubleshooting, and security

Set `DEVSTATION_TAG` to a version tag for a fixed release, or leave it unset to follow `latest`. To update, change the tag if needed, run `docker compose pull`, then `docker compose up -d`. A new image recreates the container and reinstalls the selected SDKs. Back up both the named home volume and `workspaces/`. Partial SDK versions resolve again at recreation.

If startup fails, inspect `docker compose logs devstation`. Check version syntax, upstream availability, outbound HTTPS, and disk space. If an SDK change appears ignored, inspect `docker compose config` and run `up -d` rather than `restart`. On Linux, check `DEV_UID`/`DEV_GID` and host bind mount ownership if writes fail. If Codex device login fails, check its account setting. For Claude Remote Control, run `claude doctor` and check subscription login, organization policy, project trust, API endpoint, and conflicting API variables. For editor issues, test loopback access before checking DNS, TLS, and authentication.

This is a development container, not an isolation boundary for hostile code. Agent commands and editor terminals can read mounted projects and home credentials, install packages, and reach the network. Do not mount host secrets or the Docker socket. Use a dedicated host or VM for untrusted repositories.

## Star history

<a href="https://www.star-history.com/?repos=LucUrlings%2Fagent-devstation&type=date">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/chart?repos=LucUrlings/agent-devstation&type=date&theme=dark" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/chart?repos=LucUrlings/agent-devstation&type=date" />
    <img alt="Agent Devstation GitHub star history" src="https://api.star-history.com/chart?repos=LucUrlings/agent-devstation&type=date" />
  </picture>
</a>

## Project policy

Original project code is [Apache 2.0 licensed](LICENSE). The image installs separately licensed upstream tools. We took inspiration from the use case in `icoretech/codex-docker` but did not copy its Dockerfile or scripts. See [CONTRIBUTING.md](CONTRIBUTING.md), [SECURITY.md](SECURITY.md), and the [Code of Conduct](CODE_OF_CONDUCT.md).

Protect `main` with the [documented repository ruleset](docs/repository-settings.md): require pull requests, passing CI checks, and resolved conversations; block force pushes and deletion. Require another approving reviewer only when a second trusted maintainer exists, so a solo maintainer can merge reviewed changes. Fork PR checks have read-only `contents` permission and no publication credentials. CI builds AMD64 and ARM64 concurrently on native runners. Successful CI runs for trusted `main` pushes trigger nightly publication; a full release promotes an already built commit to the version tag and `latest`.
