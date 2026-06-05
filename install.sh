#!/usr/bin/env bash
# niko-ops/install.sh

set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

AI_PLATFORMS=(claudecode codex cursor)
SELECTED_PLATFORMS=()
SELECTED_TOOLS=()
TOOLS=(superpowers gitnexus context7 ui-ux-pro-max andrej-karpathy-skills)

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

load_custom_skills() {
  local skills_dir="$REPO_DIR/skills"

  if [[ ! -d "$skills_dir" ]]; then
    return
  fi

  local skill_dir
  while IFS= read -r skill_dir; do
    TOOLS+=("[custom] $(basename "$skill_dir")")
  done < <(find "$skills_dir" -mindepth 1 -maxdepth 1 -type d -exec test -f '{}/SKILL.md' ';' -print | sort)
}

normalize_skill_name() {
  local skill_file="$1"
  local skill_name="$2"

  if [[ ! -f "$skill_file" ]]; then
    log_warn "Skill file not found at $skill_file"
    return 1
  fi

  if command -v python3 >/dev/null 2>&1; then
    python3 - "$skill_file" "$skill_name" <<'PYEOF'
import re
import sys

path, skill_name = sys.argv[1], sys.argv[2]
with open(path) as f:
    content = f.read()

content = re.sub(r"(?m)^name: .*$", f"name: {skill_name}", content, count=1)

with open(path, "w") as f:
    f.write(content)
PYEOF
  else
    log_warn "python3 not found — leaving $skill_file name unchanged"
  fi
}

# =========================
# Submodule bootstrap
# =========================

ensure_submodules() {
  log_do "Ensuring submodules are initialized..."
  git -C "$REPO_DIR" submodule update --init --recursive
  log_ok "Submodules ready"
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

deploy_custom_skill() {
  local label="$1" src="$2" dest="$3" platform="$4"

  log_do "$platform: copying $label to $dest"
  mkdir -p "$dest"
  cp -r "$src/." "$dest/"
  log_ok "$platform: $label deployed"
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
      log_do "codex: enabling official plugin"
      codex plugin add superpowers@openai-curated 2>/dev/null || true
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
    need_manual "ui-ux-pro-max" "cursor" "Restart Cursor to reload the ui-ux-pro-max skill."
  fi
}

# =========================
# andrej-karpathy-skills
# =========================

install_andrej_karpathy_skills() {
  banner "andrej-karpathy-skills"

  local src="$REPO_DIR/plugins/andrej-karpathy-skills"
  local skill_src="$src/skills/karpathy-guidelines"

  if [[ ! -d "$skill_src" ]]; then
    log_warn "Source not found at $skill_src — submodule may not be initialized"
    return 1
  fi

  if has_platform claudecode; then
    local dest="$HOME/.claude/skills/andrej-karpathy-skills"
    log_do "claudecode: copying skill to $dest"
    mkdir -p "$dest" && cp -r "$skill_src/." "$dest/"
    normalize_skill_name "$dest/SKILL.md" "andrej-karpathy-skills"
    log_ok "claudecode: skill deployed"
    if command -v claude >/dev/null 2>&1; then
      log_do "claudecode: registering via plugin marketplace"
      claude plugin marketplace add forrestchang/andrej-karpathy-skills 2>/dev/null || true
      claude plugin install andrej-karpathy-skills@karpathy-skills 2>/dev/null || true
      log_ok "claudecode: plugin registration attempted"
    else
      log_skip "claudecode: claude not installed — skipping plugin registration"
    fi
  fi

  if has_platform codex; then
    local dest="$HOME/.codex/skills/andrej-karpathy-skills"
    log_do "codex: copying skill to $dest"
    mkdir -p "$dest" && cp -r "$skill_src/." "$dest/"
    normalize_skill_name "$dest/SKILL.md" "andrej-karpathy-skills"
    log_ok "codex: skill deployed"
  fi

  if has_platform cursor; then
    local skill_dest="$HOME/.cursor/skills/andrej-karpathy-skills"
    log_do "cursor: copying skill to $skill_dest"
    mkdir -p "$skill_dest" && cp -r "$skill_src/." "$skill_dest/"
    normalize_skill_name "$skill_dest/SKILL.md" "andrej-karpathy-skills"
    log_ok "cursor: skill deployed"
  fi
}

# =========================
# custom skills
# =========================

install_custom_skill() {
  local skill_name="$1"
  local skill_src="$REPO_DIR/skills/$skill_name"
  local label="[Custom] $skill_name"

  banner "[custom] $skill_name"

  if [[ ! -f "$skill_src/SKILL.md" ]]; then
    log_warn "Source not found at $skill_src/SKILL.md"
    return 1
  fi

  if has_platform claudecode; then
    deploy_custom_skill "$label" "$skill_src" "$HOME/.claude/skills/$skill_name" "claudecode"
  fi

  if has_platform codex; then
    deploy_custom_skill "$label" "$skill_src" "$HOME/.codex/skills/$skill_name" "codex"
  fi

  if has_platform cursor; then
    deploy_custom_skill "$label" "$skill_src" "$HOME/.cursor/skills/$skill_name" "cursor"
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
    andrej-karpathy-skills) install_andrej_karpathy_skills ;;
    "[custom] "*) install_custom_skill "${1#\[custom\] }" ;;
    *) echo "❌ Unknown tool: $1"; return 1 ;;
  esac
}

# =========================
# Main
# =========================

load_custom_skills

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
