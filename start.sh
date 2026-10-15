#!/usr/bin/env bash
set -euo pipefail

export XDG_DATA_HOME="${XDG_DATA_HOME:-/root/project-data}"

WORKSPACE_DIR="${WORKSPACE_DIR:-/root/project-data/workspace}"
OPENCODE_SERVER_COMMAND="${OPENCODE_SERVER_COMMAND:-web}"
OPENCODE_DATA_DIR="${XDG_DATA_HOME}/opencode"
OPENCODE_CONFIG_DIR="${XDG_CONFIG_HOME:-/root/.config}/opencode"
AUTH_FILE="${OPENCODE_DATA_DIR}/auth.json"
GLOBAL_CONFIG_FILE="${OPENCODE_CONFIG_DIR}/opencode.json"

mkdir -p "$WORKSPACE_DIR" "$OPENCODE_DATA_DIR" "$OPENCODE_CONFIG_DIR"

# Headless environment: never hang waiting for interactive git credentials.
export GIT_TERMINAL_PROMPT=0

directory_is_empty() {
  [ -z "$(ls -A "$1" 2>/dev/null)" ]
}

normalize_repo_url() {
  case "$1" in
    git@github.com:*)
      printf 'https://github.com/%s\n' "${1#git@github.com:}"
      ;;
    *)
      printf '%s\n' "$1"
      ;;
  esac
}

clone_repo() {
  local repo_url
  repo_url="$(normalize_repo_url "$REPO_URL")"

  local depth_args=()
  if [ -n "${REPO_DEPTH:-}" ]; then
    depth_args=(--depth "$REPO_DEPTH")
  fi

  if [ -n "${REPO_BRANCH:-}" ]; then
    git clone "${depth_args[@]}" --branch "$REPO_BRANCH" "$repo_url" "$WORKSPACE_DIR"
  else
    git clone "${depth_args[@]}" "$repo_url" "$WORKSPACE_DIR"
  fi
}

configure_git_defaults() {
  git config --global user.name "${GIT_AUTHOR_NAME:-opencode on Render}"
  git config --global user.email "${GIT_AUTHOR_EMAIL:-opencode@render.example}"
  git config --global --add safe.directory "$WORKSPACE_DIR"
  # Clear inherited helpers, then route github.com through the token helper
  # so the agent can pull AND push for the lifetime of the service.
  git config --global --add credential.helper ""
  git config --global --add credential.https://github.com.helper /usr/local/bin/git-credential-github
}

ensure_workspace_project() {
  if directory_is_empty "$WORKSPACE_DIR"; then
    cat > "$WORKSPACE_DIR/README.md" <<'MD'
# opencode workspace

This is the persisted workspace for your hosted opencode agent.

Clone a repo here, create files from scratch, or redeploy with `REPO_URL` set.
MD

    cat > "$WORKSPACE_DIR/AGENTS.md" <<'MD'
# Agent notes

Work in this directory. Commit and push important changes to a remote Git repo.
MD
  fi

  if [ ! -d "$WORKSPACE_DIR/.git" ]; then
    git -C "$WORKSPACE_DIR" init -b main
  fi
}

write_auth_file() {
  AUTH_FILE="$AUTH_FILE" node <<'NODE'
const fs = require("node:fs");
const path = process.env.AUTH_FILE;

let auth = {};
try {
  auth = JSON.parse(fs.readFileSync(path, "utf8"));
} catch {
  auth = {};
}

const providers = {
  anthropic: process.env.ANTHROPIC_API_KEY,
  openai: process.env.OPENAI_API_KEY,
  openrouter: process.env.OPENROUTER_API_KEY,
  google: process.env.GEMINI_API_KEY || process.env.GOOGLE_GENERATIVE_AI_API_KEY,
  groq: process.env.GROQ_API_KEY,
  mistral: process.env.MISTRAL_API_KEY,
  xai: process.env.XAI_API_KEY,
  deepseek: process.env.DEEPSEEK_API_KEY,
};

for (const [provider, key] of Object.entries(providers)) {
  if (key) auth[provider] = { type: "api", key };
}

fs.mkdirSync(require("node:path").dirname(path), { recursive: true });
fs.writeFileSync(path, `${JSON.stringify(auth, null, 2)}\n`, { mode: 0o600 });
NODE
}

write_global_config() {
  GLOBAL_CONFIG_FILE="$GLOBAL_CONFIG_FILE" node <<'NODE'
const fs = require("node:fs");
const path = process.env.GLOBAL_CONFIG_FILE;

let config = {};
try {
  config = JSON.parse(fs.readFileSync(path, "utf8"));
} catch {
  config = {};
}

if (!config || typeof config !== "object" || Array.isArray(config)) {
  config = {};
}

config.$schema = config.$schema || "https://opencode.ai/config.json";
config.mcp = config.mcp && typeof config.mcp === "object" && !Array.isArray(config.mcp)
  ? config.mcp
  : {};
config.mcp.render = {
  type: "remote",
  url: "https://mcp.render.com/mcp",
  enabled: true,
  oauth: false,
  headers: {
    Authorization: "Bearer {env:RENDER_API_KEY}",
  },
};

// Alibaba Token Plan (Singapore). Custom OpenAI-compatible provider; these
// model IDs are not in the public models.dev catalog under this name, so the
// whole models block is declared here. Limits match the plan's real numbers
// (see ~/.config/opencode/opencode.json on the author's dev machine).
if (process.env.ALIBABA_API_KEY) {
  config.provider = config.provider && typeof config.provider === "object" && !Array.isArray(config.provider)
    ? config.provider
    : {};

  config.provider["alibaba-sg"] = {
    npm: "@ai-sdk/openai-compatible",
    name: "Alibaba Token Plan (SG)",
    options: {
      baseURL: "https://token-plan.ap-southeast-1.maas.aliyuncs.com/compatible-mode/v1",
      apiKey: "{env:ALIBABA_API_KEY}",
    },
    models: {
      auto: { name: "Qwen Auto", limit: { context: 1000000, input: 983616, output: 65536 }, modalities: { input: ["text", "image", "video"], output: ["text"] }, reasoning: true, tool_call: true, attachment: true },
      "qwen3.8-max": { name: "Qwen 3.8 Max", limit: { context: 1000000, input: 983616, output: 131072 }, modalities: { input: ["text", "image", "video", "pdf"], output: ["text"] }, reasoning: true, tool_call: true, attachment: true },
      "qwen3.8-flash": { name: "Qwen 3.8 Flash", limit: { context: 1000000, input: 983616, output: 131072 }, modalities: { input: ["text", "image", "video"], output: ["text"] }, reasoning: true, tool_call: true, attachment: true },
      "qwen3.7-max": { name: "Qwen 3.7 Max", limit: { context: 1000000, input: 983616, output: 131072 }, modalities: { input: ["text"], output: ["text"] }, reasoning: true, tool_call: true, attachment: false },
      "qwen3.7-plus": { name: "Qwen 3.7 Plus", limit: { context: 1000000, input: 983616, output: 65536 }, modalities: { input: ["text", "image", "video"], output: ["text"] }, reasoning: true, tool_call: true, attachment: true },
      "qwen3.6-flash": { name: "Qwen 3.6 Flash", limit: { context: 1000000, input: 983616, output: 65536 }, modalities: { input: ["text", "image", "video"], output: ["text"] }, reasoning: true, tool_call: true, attachment: true },
      "deepseek-v4-pro": { name: "DeepSeek V4 Pro (Alibaba)", limit: { context: 1000000, input: 1000000, output: 384000 }, modalities: { input: ["text"], output: ["text"] }, reasoning: true, tool_call: true, attachment: false },
      "deepseek-v4-pro-0813": { name: "DeepSeek V4 Pro 0813 (Alibaba)", limit: { context: 1000000, input: 1000000, output: 384000 }, modalities: { input: ["text"], output: ["text"] }, reasoning: true, tool_call: true, attachment: false },
      "deepseek-v4.1-flash": { name: "DeepSeek V4.1 Flash (Alibaba)", limit: { context: 1000000, input: 1000000, output: 384000 }, modalities: { input: ["text", "image"], output: ["text"] }, reasoning: true, tool_call: true, attachment: true },
      "deepseek-v4-flash-0731": { name: "DeepSeek V4 Flash 0731 (Alibaba)", limit: { context: 1000000, input: 1000000, output: 384000 }, modalities: { input: ["text"], output: ["text"] }, reasoning: true, tool_call: true, attachment: false },
      "glm-5.3": { name: "GLM 5.3 (Alibaba)", limit: { context: 1000000, input: 1000000, output: 131072 }, modalities: { input: ["text"], output: ["text"] }, reasoning: true, tool_call: true, attachment: false },
      "glm-5.2": { name: "GLM 5.2 (Alibaba)", limit: { context: 1000000, input: 1000000, output: 131072 }, modalities: { input: ["text"], output: ["text"] }, reasoning: true, tool_call: true, attachment: false },
    },
  };
}

if (process.env.OPENCODE_MODEL) {
  config.model = process.env.OPENCODE_MODEL;
} else if (process.env.ALIBABA_API_KEY) {
  config.model = "alibaba-sg/deepseek-v4.1-flash";
}
if (process.env.OPENCODE_SMALL_MODEL) {
  config.small_model = process.env.OPENCODE_SMALL_MODEL;
}

// Full mandate for the hosted agent, applied from the GLOBAL config so it
// survives restarts and instance resizes (interactive "allow always" saved
// approvals live in ephemeral state that a recreated instance can lose).
// Written on every boot, so a resize can never revert it.
config.permissions = [
  { action: "*", resource: "*", effect: "allow" },
];

fs.mkdirSync(require("node:path").dirname(path), { recursive: true });
fs.writeFileSync(path, `${JSON.stringify(config, null, 2)}\n`);
NODE
}

write_project_config_if_missing() {
  if [ -f "$WORKSPACE_DIR/opencode.json" ]; then
    return
  fi

  # V2 permission rules (V1's `permission`/`bash` keys are ignored by opencode
  # V2, which makes the agent fall back to `ask` for everything). This blanket
  # allow gives the hosted agent full mandate over fs, shell, and subagents.
  cat > "$WORKSPACE_DIR/opencode.json" <<'JSON'
{
  "$schema": "https://opencode.ai/config.json",
  "permissions": [
    { "action": "*", "resource": "*", "effect": "allow" }
  ]
}
JSON
}

configure_git_defaults

if [ -n "${REPO_URL:-}" ] && directory_is_empty "$WORKSPACE_DIR"; then
  clone_repo
fi

ensure_workspace_project
write_auth_file
write_global_config
write_project_config_if_missing

# OpenCode V2 serves the web UI and the HTTP API from a single `serve`
# process. HTTP basic auth is enabled when OPENCODE_SERVER_PASSWORD is set
# (username defaults to "opencode", override with OPENCODE_SERVER_USERNAME).
# Both legacy command values map to `serve`; the web UI is built in.
case "$OPENCODE_SERVER_COMMAND" in
  web|serve)
    ;;
  *)
    echo "OPENCODE_SERVER_COMMAND must be either web or serve." >&2
    exit 1
    ;;
esac

cd "$WORKSPACE_DIR"
echo "start-opencode: OpenCode V2 server starting on 0.0.0.0:${PORT:-10000} ($(date -u +%FT%TZ))"
exec opencode serve --hostname 0.0.0.0 --port "${PORT:-10000}" --print-logs
