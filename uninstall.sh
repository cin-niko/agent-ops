#!/usr/bin/env bash
# niko-ops/uninstall.sh

set -Eeuo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

AI_PLATFORMS=(claudecode codex cursor)
SELECTED_PLATFORMS=()
SELECTED_TOOLS=()
TOOLS=(superpowers gitnexus context7 ui-ux-pro-max andrej-karpathy-skills)

# Collects steps the user must do by hand after the script finishes.
MANUAL_STEPS=()

trap 'echo; echo "⚠  Cancelled"; exit 130' INT

# =========================
# Output helpers
# =========================

log_do()     { echo "  ✦ $*"; }
log_ok()     { echo "  ✓ $*"; }
log_skip()   { echo "  ○ $*"; }
log_warn()   { echo "  ⚠  $*"; }

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
    echo "✅ Uninstall complete."
    return
  fi

  echo "✅ Uninstall complete."
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

confirm() {
  local answer
  while true; do
    read -r -p "${1:-Continue?} [y/n]: " answer
    answer="$(echo "$answer" | tr '[:upper:]' '[:lower:]')"
    case "$answer" in
      y|yes) return 0 ;;
      n|no) return 1 ;;
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

has_all_platforms() {
  local p
  for p in "${AI_PLATFORMS[@]}"; do
    has_platform "$p" || return 1
  done
}

remove_path() {
  local path="$1"
  if [[ -e "$path" || -L "$path" ]]; then
    log_do "Removing $path"
    rm -rf "$path"
    log_ok "Removed $path"
  else
    log_skip "Not found: $path"
  fi
}

remove_cursor_mcp_entries() {
  local name="$1"
  shift
  local mcp_file="$HOME/.cursor/mcp.json"

  if [[ ! -f "$mcp_file" ]]; then
    log_skip "cursor: ~/.cursor/mcp.json not found"
    return
  fi

  if command -v python3 >/dev/null 2>&1; then
    log_do "cursor: removing $name MCP entry from ~/.cursor/mcp.json"
    python3 - "$mcp_file" "$name" "$@" <<'PYEOF'
import json
import sys

path = sys.argv[1]
names = sys.argv[2:]
with open(path) as f:
    cfg = json.load(f)

servers = cfg.get("mcpServers")
if isinstance(servers, dict):
    for name in names:
        servers.pop(name, None)

with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
PYEOF
    log_ok "cursor: $name MCP entry removed"
  else
    log_warn "cursor: python3 not found — skipping auto-edit"
    need_manual "$name" "cursor" "Remove the \"$name\" entry from ~/.cursor/mcp.json"
  fi
}

remove_cli_mcp_entry() {
  local cli="$1"
  local name="$2"

  if command -v "$cli" >/dev/null 2>&1; then
    log_do "$cli: removing $name MCP entry"
    "$cli" mcp remove "$name" 2>/dev/null || log_warn "$cli: MCP removal skipped"
  else
    log_skip "$cli: command not installed"
  fi
}

remove_gitnexus_skill_paths() {
  local skills_root="$1"

  remove_path "$skills_root/gitnexus-cli"
  remove_path "$skills_root/gitnexus-debugging"
  remove_path "$skills_root/gitnexus-exploring"
  remove_path "$skills_root/gitnexus-guide"
  remove_path "$skills_root/gitnexus-impact-analysis"
  remove_path "$skills_root/gitnexus-pr-review"
  remove_path "$skills_root/gitnexus-refactoring"
}

remove_claude_gitnexus_hooks() {
  local settings_file="$HOME/.claude/settings.json"

  remove_path "$HOME/.claude/hooks/gitnexus"

  if [[ ! -f "$settings_file" ]]; then
    log_skip "claudecode: ~/.claude/settings.json not found"
    return
  fi

  if command -v python3 >/dev/null 2>&1; then
    log_do "claudecode: removing GitNexus hooks from ~/.claude/settings.json"
    python3 - "$settings_file" <<'PYEOF'
import json
import sys

path = sys.argv[1]
with open(path) as f:
    cfg = json.load(f)

hooks = cfg.get("hooks")
if isinstance(hooks, dict):
    for event in list(hooks):
        entries = hooks[event]
        if not isinstance(entries, list):
            continue
        kept_entries = []
        for entry in entries:
            hook_list = entry.get("hooks") if isinstance(entry, dict) else None
            if isinstance(hook_list, list):
                hook_list = [
                    hook for hook in hook_list
                    if "gitnexus" not in str(hook.get("command", "")).lower()
                ]
                entry["hooks"] = hook_list
            if not isinstance(entry, dict) or entry.get("hooks"):
                kept_entries.append(entry)
        if kept_entries:
            hooks[event] = kept_entries
        else:
            hooks.pop(event, None)
    if not hooks:
        cfg.pop("hooks", None)

with open(path, "w") as f:
    json.dump(cfg, f, indent=2)
    f.write("\n")
PYEOF
    log_ok "claudecode: GitNexus hooks removed"
  else
    log_warn "claudecode: python3 not found — skipping auto-edit"
    need_manual "gitnexus" "claudecode" "Remove GitNexus hook entries from ~/.claude/settings.json"
  fi
}

remove_codex_superpowers_marketplace() {
  local config_file="$HOME/.codex/config.toml"

  if [[ ! -f "$config_file" ]]; then
    log_skip "codex: ~/.codex/config.toml not found"
    return
  fi

  if command -v python3 >/dev/null 2>&1; then
    log_do "codex: removing superpowers-marketplace config"
    python3 - "$config_file" <<'PYEOF'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
text = path.read_text()
patterns = [
    r'\n\[plugins\."superpowers@superpowers-marketplace"\]\nenabled = true\n',
    r'\n\[marketplaces\.superpowers-marketplace\]\n(?:.+\n)+?(?=\n\[|$)',
    r'\n\[hooks\.state\."superpowers@superpowers-marketplace:hooks/hooks\.json:session_start:0:0"\]\ntrusted_hash = ".+"\n',
]
for pattern in patterns:
    text = re.sub(pattern, '\n', text, flags=re.MULTILINE)
path.write_text(text.rstrip() + "\n")
PYEOF
    log_ok "codex: superpowers-marketplace config removed"
  else
    log_warn "codex: python3 not found — skipping auto-edit"
    need_manual "superpowers" "codex" "Remove superpowers@superpowers-marketplace and the superpowers-marketplace blocks from ~/.codex/config.toml"
  fi
}

# =========================
# Selection menus
# =========================

select_tools() {
  SELECTED_TOOLS=()
  echo "Select tools to uninstall (space-separated numbers, or 'a' for all):"
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
# superpowers
# =========================

uninstall_superpowers() {
  banner "superpowers"

  if has_platform claudecode; then
    remove_path "$HOME/.claude/skills/superpowers"
    if command -v claude >/dev/null 2>&1; then
      log_do "claudecode: uninstalling plugin"
      claude plugin uninstall superpowers 2>/dev/null || log_warn "claudecode: plugin uninstall skipped"
    else
      log_skip "claudecode: claude not installed"
    fi
  fi

  if has_platform codex; then
    remove_path "$HOME/.codex/skills/superpowers"
    if command -v codex >/dev/null 2>&1; then
      log_do "codex: removing marketplace plugin residue"
      codex plugin remove superpowers@superpowers-marketplace 2>/dev/null || log_warn "codex: marketplace plugin removal skipped"
    else
      log_skip "codex: codex not installed"
    fi
    remove_codex_superpowers_marketplace
  fi

  if has_platform cursor; then
    remove_path "$HOME/.cursor/skills/superpowers"
    need_manual "superpowers" "cursor" "In Cursor Agent chat: /remove-plugin superpowers"
  fi
}

# =========================
# gitnexus
# =========================

uninstall_gitnexus() {
  banner "gitnexus"

  if has_platform claudecode; then
    remove_cli_mcp_entry claude gitnexus
    remove_gitnexus_skill_paths "$HOME/.claude/skills"
    remove_claude_gitnexus_hooks
  fi

  if has_platform codex; then
    remove_cli_mcp_entry codex gitnexus
    remove_gitnexus_skill_paths "$HOME/.codex/skills"
  fi

  if has_platform cursor; then
    remove_cursor_mcp_entries gitnexus git-nexus
    remove_gitnexus_skill_paths "$HOME/.cursor/skills"
  fi

  if has_all_platforms && command -v npm >/dev/null 2>&1; then
    if confirm "Also uninstall the global npm package gitnexus?"; then
      log_do "npm uninstall -g gitnexus"
      npm uninstall -g gitnexus 2>&1 | grep -v "^npm warn" || true
      log_ok "npm uninstall attempted"
    else
      log_skip "npm global gitnexus left installed"
    fi
  elif has_all_platforms; then
    log_skip "npm not installed"
  else
    log_skip "npm global gitnexus left installed because not all platforms were selected"
  fi
}

# =========================
# context7
# =========================

uninstall_context7() {
  banner "context7"

  if has_platform claudecode; then
    remove_cli_mcp_entry claude context7
  fi

  if has_platform codex; then
    remove_cli_mcp_entry codex context7
  fi

  if has_platform cursor; then
    remove_cursor_mcp_entries context7
    remove_path "$HOME/.cursor/rules/context7.mdc"
  fi
}

# =========================
# ui-ux-pro-max
# =========================

uninstall_ui_ux_promax() {
  banner "ui-ux-pro-max"

  if has_platform claudecode; then
    remove_path "$HOME/.claude/skills/ui-ux-pro-max"
    if command -v claude >/dev/null 2>&1; then
      log_do "claudecode: uninstalling plugin"
      claude plugin uninstall ui-ux-pro-max 2>/dev/null || log_warn "claudecode: plugin uninstall skipped"
    else
      log_skip "claudecode: claude not installed"
    fi
  fi

  if has_platform codex; then
    remove_path "$HOME/.codex/skills/ui-ux-pro-max"
  fi

  if has_platform cursor; then
    remove_path "$HOME/.cursor/skills/ui-ux-pro-max"
  fi
}

# =========================
# andrej-karpathy-skills
# =========================

uninstall_andrej_karpathy_skills() {
  banner "andrej-karpathy-skills"

  if has_platform claudecode; then
    remove_path "$HOME/.claude/skills/andrej-karpathy-skills"
    remove_path "$HOME/.claude/skills/karpathy-guidelines"
    if command -v claude >/dev/null 2>&1; then
      log_do "claudecode: uninstalling plugin"
      claude plugin uninstall andrej-karpathy-skills 2>/dev/null || log_warn "claudecode: plugin uninstall skipped"
    else
      log_skip "claudecode: claude not installed"
    fi
  fi

  if has_platform codex; then
    remove_path "$HOME/.codex/skills/andrej-karpathy-skills"
    remove_path "$HOME/.codex/skills/karpathy-guidelines"
  fi

  if has_platform cursor; then
    remove_path "$HOME/.cursor/rules/andrej-karpathy-skills.mdc"
    remove_path "$HOME/.cursor/rules/karpathy-guidelines.mdc"
    remove_path "$HOME/.cursor/skills/andrej-karpathy-skills"
    remove_path "$HOME/.cursor/skills/karpathy-guidelines"
  fi
}

# =========================
# custom skills
# =========================

uninstall_custom_skill() {
  local skill_name="$1"

  banner "[custom] $skill_name"

  if has_platform claudecode; then
    remove_path "$HOME/.claude/skills/$skill_name"
  fi

  if has_platform codex; then
    remove_path "$HOME/.codex/skills/$skill_name"
  fi

  if has_platform cursor; then
    remove_path "$HOME/.cursor/skills/$skill_name"
  fi
}

# =========================
# Dispatcher
# =========================

uninstall_tool() {
  case "$1" in
    superpowers)   uninstall_superpowers  ;;
    gitnexus)      uninstall_gitnexus     ;;
    context7)      uninstall_context7     ;;
    ui-ux-pro-max) uninstall_ui_ux_promax ;;
    andrej-karpathy-skills) uninstall_andrej_karpathy_skills ;;
    "[custom] "*) uninstall_custom_skill "${1#\[custom\] }" ;;
    *) echo "❌ Unknown tool: $1"; return 1 ;;
  esac
}

# =========================
# Main
# =========================

load_custom_skills

banner "niko-ops uninstaller"

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

if ! confirm "Remove selected tools from selected platforms?"; then
  echo "No changes made."
  exit 0
fi

for tool in "${SELECTED_TOOLS[@]}"; do
  uninstall_tool "$tool"
done

print_summary
