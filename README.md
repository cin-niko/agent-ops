# agent-ops

Personal agent plugins. One repo, one command.

## Plugins

| Plugin | What it does | Type |
|---|---|---|
| [superpowers](https://github.com/obra/superpowers) | Structured dev workflow: plan → TDD → execute | skill |
| [gitnexus](https://github.com/abhigyanpatwari/GitNexus) | Codebase knowledge graph + MCP server | npm + MCP |
| [context7](https://github.com/upstash/context7) | Live library docs in context | MCP |
| [ui-ux-pro-max](https://github.com/nextlevelbuilder/ui-ux-pro-max-skill) | UI/UX design intelligence skill | skill |
| [andrej-karpathy-skills](https://github.com/multica-ai/andrej-karpathy-skills) | Behavioral coding guidelines: think first, keep changes simple and surgical, verify goals | skill |

## Fresh machine setup

```bash
git clone https://github.com/agent/agent-ops.git
cd agent-ops
bash install.sh
```

The installer initializes all plugin submodules automatically.

## Uninstall

```bash
bash uninstall.sh
```

## Update all plugins

```bash
git submodule update --remote --merge
git add .
git commit -m "chore: bump submodules"
```

Or just re-run `bash install.sh` and answer `y` when asked to pull latest.

## Repo layout

```
agent-ops/
├── install.sh          # run this
├── uninstall.sh        # remove installed tools
├── .gitmodules         # submodule declarations
├── plugins/              # git submodules (external plugins, not committed)
│   ├── superpowers/
│   ├── gitnexus/
│   ├── context7/
│   ├── ui-ux-pro-max/
│   └── andrej-karpathy-skills/
├── skills/             # your own custom skills (committed here)
├── mcp/                # any MCP servers you author (committed here)
└── configs/
    ├── .claude/        # CLAUDE.md, settings fragments
    ├── .codex/         # AGENTS.md, config snippets
    └── cursor/         # .cursor/rules
```

## Supported platforms

- **claudecode** — Claude Code CLI
- **codex** — OpenAI Codex CLI
- **cursor** — Cursor IDE (skills via `~/.cursor/skills/`, MCP via `~/.cursor/mcp.json`)
