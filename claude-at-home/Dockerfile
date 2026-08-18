# https://developers.home-assistant.io/docs/apps/configuration#app-dockerfile
ARG BUILD_FROM=ghcr.io/home-assistant/base:3.23
FROM ${BUILD_FROM}

# Runtime deps:
#   tmux      - holds the persistent Claude session
#   ttyd      - serves that tmux session as the ingress web terminal
#   git       - HA configs are usually git-tracked, and Claude works on them
#   openssh-client - so git can push over SSH (keys live in /data/.ssh)
#   python3   - HA configs contain Python (pyscript, AppDaemon, helpers)
#   jq / docker-cli - inspecting the Supervisor API and the Docker layer
#               (the latter only works with Protection mode off)
#   libstdc++ / gcompat - the Claude Code native build is glibc-linked
RUN apk add --no-cache \
        tmux \
        ttyd \
        git \
        openssh-client \
        python3 \
        curl \
        jq \
        docker-cli \
        libstdc++ \
        gcompat

# Bake the Claude Code CLI into the image so first boot needs no ~283MB
# download. Installed under /opt/claude-home; the claude service seeds it
# into /data (the persistent volume) on first run and then always runs with
# HOME=/data, so credentials, history and self-updates persist across
# container rebuilds.
ENV CLAUDE_SEED_HOME=/opt/claude-home
RUN mkdir -p "${CLAUDE_SEED_HOME}" \
    && HOME="${CLAUDE_SEED_HOME}" curl -fsSL https://claude.ai/install.sh | HOME="${CLAUDE_SEED_HOME}" bash \
    && test -x "${CLAUDE_SEED_HOME}/.local/bin/claude"

# Home Assistant agent skills (MIT, github.com/homeassistant-ai/skills),
# vendored as a git submodule and pinned to a commit. Baked into the image
# rather than into /data, so updating the app updates the skills too.
COPY vendor/ha-skills/skills /opt/ha-skills/skills
COPY vendor/ha-skills/LICENSE /opt/ha-skills/LICENSE

# Copy root filesystem
COPY rootfs /

RUN chmod +x \
        /etc/cont-init.d/*.sh \
        /etc/services.d/*/run \
        /etc/services.d/*/finish

LABEL \
    org.opencontainers.image.title="Home Assistant App: Claude at Home" \
    org.opencontainers.image.description="Persistent Claude Code session with an ingress-only web terminal in your sidebar" \
    org.opencontainers.image.source="https://github.com/Infraviored/claude-at-home" \
    org.opencontainers.image.licenses="MIT"
