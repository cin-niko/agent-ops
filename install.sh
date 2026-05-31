#!/usr/bin/env bash
# niko-ops/install.sh

set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

AI_PLATFORMS=(claudecode codex cursor)
SELECTED_PLATFORMS=()
SELECTED_TOOLS=()
TOOLS=(superpowers gitnexus context7 ui-ux-pro-max)

# Collects steps the user must do by hand after the script finishes
MANUAL_STEPS=()

trap 'echo; echo "⚠  Cancelled"; exit 130' INT

# =========================
# Output helpers
# =========================

# Automated action happening right now
log_do()     { echo "  ✦ $*"; }
# Automated action completed successfully
log_ok()     { echo "  ✓ $*"; }
# Automated action skipped (tool not installed, etc.)
log_skip()   { echo "  ○ $*"; }
# Warning — something unexpected but non-fatal
log_warn()   { echo "  ⚠  $*"; }

# Queue a manual step to be printed in the final summary
need_manual() {
  local tool="$1" platform="$2" instruction="$3"
  MANUAL_STEPS+=("[$tool / $platform]  $instruction")
}

banner() {
  local line
  line="$(printf '─%.0s' {1..40})"
  echo
  echo "$line"
  echo "  $1"
  echo "$line"
}

print_summary() {
  echo
  if [[ ${#MANUAL_STEPS[@]} -eq 0 ]]; then
    echo "✅ Done — everything was configured automatically."
    return
  fi

  echo "✅ Install complete."
  echo
  printf '═%.0s' {1..40}; echo
  echo "  ACTION REQUIRED — complete these steps manually:"
  printf '═%.0s' {1..40}; echo
  echo
  local i=1
  for step in "${MANUAL_STEPS[@]}"; do
    printf "  %d) %s\n" "$i" "$step"
    ((i++))
  done
  echo
}

# =========================
# Utils
# =========================

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "❌ Required command not found: $1 — please install it and try again."
    exit 1
  }
}

confirm() {
  local answer
  while true; do
    read -r -p "${1:-Continue?} [y/n]: " answer
    answer="$(echo "$answer" | tr '[:upper:]' '[:lower:]')"
    case "$answer" in
      y|yes) return 0 ;; n|no) return 1 ;;
      *) echo "Please enter y or n" ;;
    esac
  done
}

has_platform() { printf '%s\n' "${SELECTED_PLATFORMS[@]}" | grep -qx "$1"; }

# =========================
# Submodule bootstrap
# =========================

ensure_submodules() {
  if [[ ! -f "$REPO_DIR/plugins/superpowers/README.md" ]]; then
    log_do "Initializing submodules (first run)..."
    git -C "$REPO_DIR" submodule update --init --recursive
  fi
}

update_submodules() {
  log_do "Pulling latest for all submodules..."
  git -C "$REPO_DIR" submodule update --remote --merge
}

# =========================
# Selection menus
# =========================

select_tools() {
  SELECTED_TOOLS=()
  echo "Select tools to install (space-separated numbers, or 'a' for all):"
  echo
  local i=1
  for t in "${TOOLS[@]}"; do printf "  %d) %s\n" "$i" "$t"; ((i++)); done
  echo
  read -r -p "Selection: " choices

  if [[ "$choices" == "a" ]]; then
    SELECTED_TOOLS=("${TOOLS[@]}")
    return
  fi

  declare -A seen=()
  for c in $choices; do
    [[ "$c" =~ ^[0-9]+$ ]] || { log_warn "Skipping invalid: $c"; continue; }
    local idx=$((c - 1))
    local t="${TOOLS[$idx]:-}"
    [[ -n "$t" ]] || { log_warn "Out of range: $c"; continue; }
    [[ -z "${seen[$t]:-}" ]] && { SELECTED_TOOLS+=("$t"); seen["$t"]=1; }
  done
}

select_platforms() {
  SELECTED_PLATFORMS=()
  echo "Select platforms (space-separated numbers, or 'a' for all):"
  echo
  local i=1
  for p in "${AI_PLATFORMS[@]}"; do printf "  %d) %s\n" "$i" "$p"; ((i++)); done
  echo

  while true; do
    read -r -p "Selection: " choices

    if [[ "$choices" == "a" ]]; then
      SELECTED_PLATFORMS=("${AI_PLATFORMS[@]}")
      return
    fi

    declare -A seen_p=()
    local valid=()
    for c in $choices; do
      [[ "$c" =~ ^[0-9]+$ ]] || { log_warn "Invalid: $c"; continue; }
      local idx=$((c - 1))
      local p="${AI_PLATFORMS[$idx]:-}"
      [[ -n "$p" ]] || { log_warn "Out of range: $c"; continue; }
      [[ -z "${seen_p[$p]:-}" ]] && { valid+=("$p"); seen_p["$p"]=1; }
    done
    [[ ${#valid[@]} -gt 0 ]] && { SELECTED_PLATFORMS=("${valid[@]}"); return; }
    echo "No valid selection, try again"
  done
}

# =========================
# Deploy helper
# =========================

deploy_submodule() {
  local name="$1" dest="$2"
  local src="$REPO_DIR/plugins/$name"

  if [[ ! -d "$src" ]]; then
    log_warn "Submodule missing at $src — run: git submodule update --init"
    return 1
  fi

  if [[ -d "$dest/.git" ]]; then
    log_do "Syncing $dest"
    git -C "$dest" pull --ff-only 2>/dev/null || log_warn "Pull skipped (local changes?)"
  elif [[ -d "$dest" && "$(ls -A "$dest" 2>/dev/null)" ]]; then
    log_do "Syncing $dest"
    rsync -a --delete "$src/" "$dest/"
  else
    log_do "Copying to $dest"
    mkdir -p "$(dirname "$dest")"
    cp -r "$src" "$dest"
  fi
  log_ok "Deployed → $dest"
}

# =========================
# superpowers
# =========================

install_superpowers() {
  banner "superpowers"

  if has_platform claudecode; then
    deploy_submodule superpowers "$HOME/.claude/skills/superpowers"
    if command -v claude >/dev/null 2>&1; then
      log_do "claudecode: registering plugin"
      if ! claude plugin install superpowers@claude-plugins-official 2>/dev/null; then
        claude plugin marketplace add obra/superpowers-marketplace 2>/dev/null || true
        claude plugin install superpowers@superpowers-marketplace 2>/dev/null || true
      fi
      log_ok "claudecode: plugin registered"
    else
      log_skip "claudecode: claude not installed — skipping plugin registration"
    fi
  fi

  if has_platform codex; then
    deploy_submodule superpowers "$HOME/.codex/skills/superpowers"
    if command -v codex >/dev/null 2>&1; then
      log_do "codex: adding marketplace + plugin"
      codex plugin marketplace add https://github.com/obra/superpowers-marketplace 2>/dev/null || true
      codex plugin add superpowers@superpowers-marketplace 2>/dev/null || true
      log_ok "codex: plugin registered"
    else
      log_skip "codex: codex not installed — skipping plugin registration"
    fi
    local bootstrap="$HOME/.codex/skills/superpowers/.codex/superpowers-codex"
    if [[ -x "$bootstrap" ]]; then
      log_do "codex: running bootstrap"
      "$bootstrap" bootstrap || true
      log_ok "codex: bootstrap done"
    fi
  fi

  if has_platform cursor; then
    deploy_submodule superpowers "$HOME/.cursor/skills/superpowers"
    log_ok "cursor: skill deployed to ~/.cursor/skills/superpowers"
    need_manual "superpowers" "cursor" "In Cursor Agent chat: /add-plugin superpowers"
  fi
}

# =========================
# gitnexus
# =========================

install_gitnexus() {
  banner "gitnexus"
  require_cmd npm

  log_do "npm install -g gitnexus"
  npm install -g gitnexus 2>&1 | grep -v "^npm warn" || true
  require_cmd gitnexus

  log_do "gitnexus setup"
  gitnexus setup

  if has_platform claudecode; then
    if command -v claude >/dev/null 2>&1; then
      log_do "claudecode: registering gitnexus MCP"
      claude mcp add gitnexus -- npx -y gitnexus@latest mcp 2>/dev/null || true
      log_ok "claudecode: gitnexus MCP registered"
    else
      log_skip "claudecode: claude not installed"
    fi
  fi

  if has_platform codex; then
    if command -v codex >/dev/null 2>&1; then
      log_do "codex: registering gitnexus MCP"
      codex mcp add gitnexus -- npx -y gitnexus@latest mcp 2>/dev/null || true
      log_ok "codex: gitnexus MCP registered"
    else
      log_skip "codex: codex not installed"
    fi
  fi

  if has_platform cursor; then
    local mcp_file="$HOME/.cursor/mcp.json"
    [[ -f "$mcp_file" ]] || echo '{"mcpServers":{}}' > "$mcp_file"
    if command -v python3 >/dev/null 2>&1; then
      log_do "cursor: writing gitnexus MCP entry to ~/.cursor/mcp.json"
      python3 - "$mcp_file" <<'PYEOF'
import json, sys
path = sys.argv[1]
with open(path) as f: cfg = json.load(f)
cfg.setdefault("mcpServers", {})["gitnexus"] = {
  "command": "npx", "args": ["-y", "gitnexus@latest", "mcp"]
}
with open(path, "w") as f: json.dump(cfg, f, indent=2)
PYEOF
      log_ok "cursor: gitnexus MCP entry written"
    else
      log_warn "cursor: python3 not found — skipping auto-write"
      need_manual "gitnexus" "cursor" 'Add to ~/.cursor/mcp.json → "gitnexus": {"command":"npx","args":["-y","gitnexus@latest","mcp"]}'
    fi
  fi

  need_manual "gitnexus" "all platforms" "cd into each repo and run: gitnexus analyze"
}

# =========================
# context7
# =========================

install_context7() {
  banner "context7"
  require_cmd npx

  if has_platform claudecode; then
    if command -v claude >/dev/null 2>&1; then
      log_do "claudecode: registering context7 MCP"
      claude mcp add context7 -- npx -y @upstash/context7-mcp 2>/dev/null || true
      log_ok "claudecode: context7 MCP registered"
    else
      log_skip "claudecode: claude not installed"
    fi
  fi

  if has_platform codex; then
    if command -v codex >/dev/null 2>&1; then
      log_do "codex: registering context7 MCP"
      codex mcp add context7 -- npx -y @upstash/context7-mcp 2>/dev/null || true
      log_ok "codex: context7 MCP registered"
    else
      log_skip "codex: codex not installed"
    fi
  fi

  if has_platform cursor; then
    local mcp_file="$HOME/.cursor/mcp.json"
    [[ -f "$mcp_file" ]] || echo '{"mcpServers":{}}' > "$mcp_file"
    if command -v python3 >/dev/null 2>&1; then
      log_do "cursor: writing context7 MCP entry to ~/.cursor/mcp.json"
      python3 - "$mcp_file" <<'PYEOF'
import json, sys
path = sys.argv[1]
with open(path) as f: cfg = json.load(f)
cfg.setdefault("mcpServers", {})["context7"] = {
  "command": "npx", "args": ["-y", "@upstash/context7-mcp"]
}
with open(path, "w") as f: json.dump(cfg, f, indent=2)
PYEOF
      log_ok "cursor: context7 MCP entry written"
    else
      log_warn "cursor: python3 not found — skipping auto-write"
      need_manual "context7" "cursor" 'Add to ~/.cursor/mcp.json → "context7": {"command":"npx","args":["-y","@upstash/context7-mcp"]}'
    fi
  fi
}

# =========================
# ui-ux-pro-max
# =========================

install_ui_ux_promax() {
  banner "ui-ux-pro-max"

  local src="$REPO_DIR/plugins/ui-ux-pro-max/src/ui-ux-pro-max"
  if [[ ! -d "$src" ]]; then
    log_warn "Source not found at $src — submodule may not be initialized"
    return 1
  fi

  if has_platform claudecode; then
    local dest="$HOME/.claude/skills/ui-ux-pro-max"
    log_do "claudecode: copying skill to $dest"
    mkdir -p "$dest" && cp -r "$src/." "$dest/"
    log_ok "claudecode: skill deployed"
    if command -v claude >/dev/null 2>&1; then
      log_do "claudecode: registering via plugin marketplace"
      claude plugin marketplace add nextlevelbuilder/ui-ux-pro-max-skill 2>/dev/null || true
      claude plugin install ui-ux-pro-max@ui-ux-pro-max-skill 2>/dev/null || true
      log_ok "claudecode: plugin registered"
    else
      log_skip "claudecode: claude not installed — skipping plugin registration"
    fi
  fi

  if has_platform codex; then
    local dest="$HOME/.codex/skills/ui-ux-pro-max"
    log_do "codex: copying skill to $dest"
    mkdir -p "$dest" && cp -r "$src/." "$dest/"
    log_ok "codex: skill deployed"
  fi

  if has_platform cursor; then
    local dest="$HOME/.cursor/skills/ui-ux-pro-max"
    log_do "cursor: copying skill to $dest"
    mkdir -p "$dest" && cp -r "$src/." "$dest/"
    log_ok "cursor: skill deployed to ~/.cursor/skills/ui-ux-pro-max"
    need_manual "ui-ux-pro-max" "cursor" "In Cursor Agent chat: /add-plugin ui-ux-pro-max"
  fi
}

# =========================
# Dispatcher
# =========================

install_tool() {
  case "$1" in
    superpowers)   install_superpowers  ;;
    gitnexus)      install_gitnexus     ;;
    context7)      install_context7     ;;
    ui-ux-pro-max) install_ui_ux_promax ;;
    *) echo "❌ Unknown tool: $1"; return 1 ;;
  esac
}

# =========================
# Main
# =========================

banner "niko-ops installer"

ensure_submodules

echo
select_platforms
echo
echo "  Platforms: ${SELECTED_PLATFORMS[*]}"
echo

select_tools

if [[ ${#SELECTED_TOOLS[@]} -eq 0 ]]; then
  echo "No tools selected."
  exit 0
fi

echo
echo "  Tools: ${SELECTED_TOOLS[*]}"
echo

if confirm "Pull latest submodule versions before installing?"; then
  update_submodules
fi

for tool in "${SELECTED_TOOLS[@]}"; do
  install_tool "$tool"
done

print_summary