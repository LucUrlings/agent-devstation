FROM ubuntu:24.04

LABEL org.opencontainers.image.source="https://github.com/LucUrlings/agent-devstation"

ARG TARGETARCH
ARG CODE_SERVER_VERSION=4.138.0

ENV DEBIAN_FRONTEND=noninteractive \
    HOME=/home/dev \
    CODEX_HOME=/home/dev/.codex \
    DOTNET_ROOT=/opt/sdk/dotnet/current \
    JAVA_HOME=/opt/sdk/java/current \
    GOROOT=/opt/sdk/go/current \
    GOPATH=/home/dev/go \
    CARGO_HOME=/opt/sdk/rust/current \
    RUSTUP_HOME=/opt/sdk/rust/rustup \
    UV_PYTHON_INSTALL_DIR=/opt/sdk/python \
    PATH=/opt/sdk/python/current/bin:/opt/sdk/node/current/bin:/opt/sdk/dotnet/current:/opt/sdk/java/current/bin:/opt/sdk/go/current/bin:/home/dev/go/bin:/opt/sdk/rust/current/bin:/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin

RUN apt-get update && apt-get install -y --no-install-recommends \
      bash ca-certificates curl git gnupg gosu jq openssh-client procps \
      sudo passwd tar unzip xz-utils zstd build-essential libicu74 libssl3t64 \
    && rm -rf /var/lib/apt/lists/* \
    && if id -u ubuntu >/dev/null 2>&1; then usermod -l dev -d /home/dev -m ubuntu && groupmod -n dev ubuntu; else useradd -m -u 1000 -s /bin/bash dev; fi \
    && mkdir -p /workspaces /opt/sdk /home/dev/.codex /home/dev/.config /home/dev/.local \
    && chown -R dev:dev /workspaces /home/dev

# Official standalone Codex release. The installer is executed only at image build time.
RUN curl -fsSL https://chatgpt.com/codex/install.sh -o /tmp/install-codex.sh \
    && HOME=/root CODEX_HOME=/opt/codex sh /tmp/install-codex.sh \
    && ln -s /opt/codex/packages /home/dev/.codex/packages \
    && chown -R dev:dev /opt/codex /home/dev/.codex \
    && rm /tmp/install-codex.sh \
    && /opt/codex/packages/standalone/current/bin/codex --version

# Anthropic's signed stable apt repository keeps the CLI outside user SDK paths.
RUN install -d -m 0755 /etc/apt/keyrings \
    && curl -fsSL https://downloads.claude.ai/keys/claude-code.asc -o /etc/apt/keyrings/claude-code.asc \
    && echo 'deb [signed-by=/etc/apt/keyrings/claude-code.asc] https://downloads.claude.ai/claude-code/apt/stable stable main' > /etc/apt/sources.list.d/claude-code.list \
    && apt-get update && apt-get install -y --no-install-recommends claude-code \
    && rm -rf /var/lib/apt/lists/* \
    && claude --version

# The standalone editor bundles its private Node runtime. It never adds node to PATH.
RUN curl -fsSL "https://github.com/coder/code-server/releases/download/v${CODE_SERVER_VERSION}/code-server-${CODE_SERVER_VERSION}-linux-${TARGETARCH}.tar.gz" -o /tmp/code-server.tar.gz \
    && mkdir -p /opt/code-server \
    && tar -xzf /tmp/code-server.tar.gz --strip-components=1 -C /opt/code-server \
    && ln -s /opt/code-server/bin/code-server /usr/local/bin/code-server \
    && rm /tmp/code-server.tar.gz \
    && code-server --version

RUN curl -fsSL https://astral.sh/uv/install.sh -o /tmp/install-uv.sh \
    && UV_INSTALL_DIR=/usr/local/bin sh /tmp/install-uv.sh \
    && rm /tmp/install-uv.sh \
    && uv --version

COPY scripts/entrypoint.sh scripts/install-sdks.sh /usr/local/lib/agent-devstation/
COPY scripts/codex.sh /usr/local/bin/codex
RUN chmod 0755 /usr/local/lib/agent-devstation/*.sh /usr/local/bin/codex && chown -R dev:dev /home/dev

WORKDIR /workspaces
EXPOSE 8080
ENTRYPOINT ["/usr/local/lib/agent-devstation/entrypoint.sh"]
