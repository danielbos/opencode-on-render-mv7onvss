# opencode on Render

Run opencode as a hosted AI coding agent with the browser UI and `opencode attach`.

[![Deploy to Render](https://render.com/images/deploy-to-render-button.svg)](https://render.com/deploy-template/api/github/start?template_repo=opencode-on-render)

## What you get

- A single Render Web Service running `opencode web`
- The built-in opencode web UI on your Render URL
- Remote TUI access with `opencode attach`
- A `pro_plus` instance to avoid OOM loops on startup and active agent sessions
- A 1 GB persistent disk for opencode state and your working tree
- Optional repo cloning into `/root/project-data/workspace` on first boot
- GitHub CLI (`gh`) and token-based push/pull access to private repos
- The Render OpenCode plugin installed by default

## How to use it

### From your browser

Deploy the template, then open the Render service URL.

Log in with:

- Username: `opencode`
- Password: the generated `OPENCODE_SERVER_PASSWORD` value in the Render Dashboard

### From your terminal

Install opencode locally:

```bash
npm install -g opencode-ai
```

Attach to your hosted backend:

```bash
opencode attach https://your-service.onrender.com
```

Use the generated password when prompted. You can also pass it directly:

```bash
opencode attach https://your-service.onrender.com \
  --username opencode \
  --password "$OPENCODE_SERVER_PASSWORD"
```

## Bring your own repo

Set `REPO_URL` during deploy to clone a working tree into `/root/project-data/workspace` on first boot.

For a public repo:

```txt
REPO_URL=https://github.com/your-org/your-repo.git
```

For a specific branch:

```txt
REPO_URL=https://github.com/your-org/your-repo.git
REPO_BRANCH=main
```

### Private GitHub repo example

To run the agent against a private repo such as `sensei-radical-transparency/sensei`, set:

```txt
REPO_URL=https://github.com/sensei-radical-transparency/sensei.git
REPO_BRANCH=main
GITHUB_TOKEN=<your token>
```

Create the token at <https://github.com/settings/personal-access-tokens/new> as a fine-grained token:

- Repository access: only select the `sensei` repo
- Permissions: `Contents` -> Read and write (clone, commit, push), `Pull requests` -> Read and write, `Metadata` -> Read-only

The startup script configures a git credential helper that reads `GITHUB_TOKEN` from the environment, so inside the web UI the agent can `git pull`, `git push`, and push branches without the token being stored in the repo or on disk. The `gh` CLI also picks up `GITHUB_TOKEN` automatically, so the agent can run `gh pr create`, `gh issue list`, and `gh pr checks` right away.

The startup script only clones when `/root/project-data/workspace` is empty. If `/root/project-data/workspace` already has files, it leaves them alone. On an existing deployment, either delete the disk (or the service) and redeploy, or ask the agent to run `git clone https://github.com/sensei-radical-transparency/sensei.git /root/project-data/workspace` itself.

If you do not set `REPO_URL`, the service creates a small default Git project in `/root/project-data/workspace` so the web UI has a project to open.

### Clone depth

Clones are full by default so pushing branches and PRs works reliably. To save time and disk on a large repo, set:

```txt
REPO_DEPTH=1
```

## Server command

The template defaults to:

```txt
OPENCODE_SERVER_COMMAND=web
```

That starts opencode's web UI and API on the same Render URL.

If `opencode attach` returns HTML instead of API responses, switch to the headless server:

```txt
OPENCODE_SERVER_COMMAND=serve
```

## Configured providers

Set one or more provider keys once in the Render Dashboard (Environment tab). They are written into opencode's auth file on every boot, so you never have to enter them in the UI:

- `ANTHROPIC_API_KEY` unlocks Anthropic models.
- `OPENAI_API_KEY` unlocks OpenAI models.
- `OPENROUTER_API_KEY` unlocks OpenRouter models.
- `GEMINI_API_KEY` (or `GOOGLE_GENERATIVE_AI_API_KEY`) unlocks Google models.
- `GROQ_API_KEY` unlocks Groq models.
- `MISTRAL_API_KEY` unlocks Mistral models.
- `XAI_API_KEY` unlocks xAI (Grok) models.
- `DEEPSEEK_API_KEY` unlocks DeepSeek models.
- `RENDER_API_KEY` unlocks Render MCP tools.

The service writes these keys into `/root/project-data/opencode/auth.json` using opencode's API-key auth format. That file lives on the persistent disk, so keys you enter manually in the UI also survive restarts and redeploys — but env vars are the way to make them survive a disk wipe or a fresh deploy.

Anthropic OAuth is not supported in this hosted setup. Use `ANTHROPIC_API_KEY`.

### Default model

To preselect the model the agent starts with, set:

```txt
OPENCODE_MODEL=anthropic/claude-sonnet-4-5
```

Use the `provider/model` format. Any model from a provider you configured a key for works, for example `openai/gpt-5`, `google/gemini-2.5-pro`, or `openrouter/deepseek/deepseek-chat-v3.1`. Optionally set `OPENCODE_SMALL_MODEL` for the cheaper model opencode uses for background tasks like title generation:

```txt
OPENCODE_SMALL_MODEL=anthropic/claude-haiku-4-5
```

You can still switch models per session in the UI; these env vars only set the starting default on boot.

## Security notes

This template gives you a remote coding agent, not a hardened sandbox.

The agent can read and write files in its workspace, run shell commands, and use the environment variables you provide. Treat it like a single-tenant development box that can act with your credentials.

Be careful with `RENDER_API_KEY`. Render API keys are broad credentials today. If you set one, opencode can use Render MCP tools with whatever access that key has. Leave `RENDER_API_KEY` unset unless you want the agent to manage Render resources from this service. Remove it when you do not need Render MCP, and rotate it if you expose logs, transcripts, or the service password.

Do not use this template with untrusted users, untrusted prompts, or repos you do not want an AI agent to execute code from.

## Instance size

The template uses Render's `pro_plus` plan (4 CPU / 8 GB) by default to give several parallel agent sessions room, especially with the web UI, provider metadata, plugins, MCP tools, and active coding sessions. Scale up or down in `render.yaml` under `plan:`:

## What's pre-wired

The image installs the Render OpenCode plugin from GitHub. It adds:

- `render_validate_blueprint`
- automatic validation when an agent edits `render.yaml` or `render.yml`
- `/deploy-to-render`
- `/check-render-status`
- the `@render` subagent
- bundled Render skills

The startup script also merges the Render MCP server into `~/.config/opencode/opencode.json`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "mcp": {
    "render": {
      "type": "remote",
      "url": "https://mcp.render.com/mcp",
      "enabled": true,
      "oauth": false,
      "headers": {
        "Authorization": "Bearer {env:RENDER_API_KEY}"
      }
    }
  }
}
```

Set `RENDER_API_KEY` in Render before asking opencode to manage Render resources.

## Disk size

The template starts with a 1 GB persistent disk mounted at:

```txt
/root/project-data
```

The startup script uses that disk for:

- `/root/project-data/opencode` for opencode auth, sessions, and SQLite state
- `/root/project-data/workspace` for the repo or project files the agent edits

To resize it, edit `render.yaml`:

```yaml
disk:
  name: opencode-data
  mountPath: /root/project-data
  sizeGB: 5
```

Then deploy the updated Blueprint.

## Known limitations

- Anthropic OAuth login does not work for hosted opencode. Use `ANTHROPIC_API_KEY`.
- The opencode web UI fetches assets from opencode's CDN at runtime.
- This is single-tenant. Do not share one deployment with multiple users.
- `/root/project-data/workspace` persists across restarts and deploys, but you should still commit and push important work back to your repo.
- The image preinstalls TypeScript language server only. Other language servers can be installed in your repo or a fork of this template.

## Learn more

- [opencode docs](https://opencode.ai/docs)
- [opencode CLI docs](https://opencode.ai/docs/cli/)
- [opencode MCP docs](https://opencode.ai/docs/mcp-servers/)
- [Render OpenCode plugin](https://github.com/render-oss/render-opencode-plugin)
