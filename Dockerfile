FROM node:24-bookworm-slim

ENV NODE_ENV=production
ENV NPM_CONFIG_UPDATE_NOTIFIER=false
ENV NPM_CONFIG_FUND=false
ENV NPM_CONFIG_AUDIT=false

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        git \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI so the agent can manage pull requests, issues, and checks.
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# Pin an explicit opencode version so upgrades are deliberate and bust the
# build cache (a plain `@latest` step gets skipped when the layer is cached,
# so deploys silently keep serving the older binary). To upgrade, bump
# OPENCODE_VERSION and redeploy. Find the newest with: npm view opencode-ai version
ARG OPENCODE_VERSION=1.19.0
RUN npm install -g \
        opencode-ai@${OPENCODE_VERSION} \
        typescript-language-server@latest \
        typescript@latest \
    && npm cache clean --force

RUN curl -fsSL https://raw.githubusercontent.com/render-oss/render-opencode-plugin/main/install.sh \
    | bash -s -- --force

WORKDIR /workspace

COPY start.sh /usr/local/bin/start-opencode
COPY git-credential-github /usr/local/bin/git-credential-github
RUN chmod +x /usr/local/bin/start-opencode /usr/local/bin/git-credential-github

EXPOSE 10000

CMD ["/usr/local/bin/start-opencode"]
