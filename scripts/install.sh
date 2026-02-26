#!/bin/bash
set -euo pipefail

# agent-sim installer
# Usage: curl -fsSL https://raw.githubusercontent.com/pproenca/agent-sim/master/scripts/install.sh | bash

VERSION="${AGENT_SIM_VERSION:-latest}"
INSTALL_DIR="${AGENT_SIM_DIR:-$HOME/.local/lib/agent-sim}"
BIN_DIR="${AGENT_SIM_BIN:-$HOME/.local/bin}"
BIN_LINK="$BIN_DIR/agent-sim"
REPO="pproenca/agent-sim"
FORCE="${AGENT_SIM_FORCE:-0}"
DOWNLOAD_URL_OVERRIDE="${AGENT_SIM_URL:-}"
SKIP_PREREQS="${AGENT_SIM_SKIP_PREREQS:-0}"
SCOPE="${AGENT_SIM_SCOPE:-}"
PROJECT_DIR="${AGENT_SIM_PROJECT_DIR:-$PWD}"
REGISTER_CLAUDE="${AGENT_SIM_REGISTER_CLAUDE:-1}"
REGISTER_OPENCODE="${AGENT_SIM_REGISTER_OPENCODE:-1}"

# --- Colors ---
red()   { printf "\033[31m%s\033[0m\n" "$1"; }
green() { printf "\033[32m%s\033[0m\n" "$1"; }
dim()   { printf "\033[2m%s\033[0m\n" "$1"; }
bold()  { printf "\033[1m%s\033[0m\n" "$1"; }
warn()  { printf "\033[33m%s\033[0m\n" "$1"; }

fail() {
  red "$1"
  exit 1
}

require_scope() {
  case "$1" in
    user|project|none) return 0 ;;
    *)
      fail "Invalid AGENT_SIM_SCOPE='$1'. Expected: user, project, or none."
      ;;
  esac
}

resolve_scope() {
  if [[ -n "$SCOPE" ]]; then
    require_scope "$SCOPE"
    return
  fi

  if [[ -t 0 ]]; then
    echo "Where should agent-sim AI assets be installed?"
    echo "  1) user    (~/.claude + ~/.config/opencode) [default]"
    echo "  2) project ($PROJECT_DIR/.claude + $PROJECT_DIR/.opencode)"
    echo "  3) none    (skip AI asset registration)"
    printf "Choose [1-3]: "
    read -r choice
    case "$choice" in
      ""|1) SCOPE="user" ;;
      2) SCOPE="project" ;;
      3) SCOPE="none" ;;
      *)
        warn "Unknown choice '$choice'. Defaulting to user scope."
        SCOPE="user"
        ;;
    esac
  else
    SCOPE="user"
  fi
}

copy_skill_dirs() {
  local src="$1"
  local dst="$2"
  local copied=0

  [[ -d "$src" ]] || return 0
  [[ -n "$dst" ]] || fail "skill destination path is empty"
  mkdir -p "$dst"

  for skill_dir in "$src"/*; do
    [[ -d "$skill_dir" ]] || continue
    local skill_name
    skill_name="$(basename "$skill_dir")"
    rm -rf -- "$dst/${skill_name:?}"
    cp -R "$skill_dir" "$dst/$skill_name"
    copied=1
  done

  if [[ "$copied" -eq 1 ]]; then
    dim "  Skills synced: $dst"
  fi
}

copy_opencode_commands() {
  local src="$1"
  local dst="$2"
  local mapping=(
    "new.md:agentsim-new.md"
    "replay.md:agentsim-replay.md"
    "apply.md:agentsim-apply.md"
    "critique.md:agentsim-critique.md"
    "tests.md:agentsim-tests.md"
  )

  [[ -d "$src" ]] || return 0
  mkdir -p "$dst"

  for pair in "${mapping[@]}"; do
    local src_file="${pair%%:*}"
    local dst_file="${pair##*:}"
    [[ -f "$src/$src_file" ]] || continue
    cp "$src/$src_file" "$dst/$dst_file"
  done

  dim "  Commands synced: $dst"
}

# --- Prerequisites ---
check_prerequisites() {
  if [[ "$SKIP_PREREQS" == "1" ]]; then
    warn "Skipping prerequisite checks (AGENT_SIM_SKIP_PREREQS=1)."
    return
  fi

  local failed=0

  # macOS
  if [[ "$(uname)" != "Darwin" ]]; then
    fail "agent-sim requires macOS."
  fi

  # Apple Silicon
  if [[ "$(uname -m)" != "arm64" ]]; then
    fail "agent-sim requires Apple Silicon (arm64). Intel Macs are not supported."
  fi

  # Xcode + simctl
  if ! xcode-select -p &>/dev/null; then
    red "Xcode is not installed."
    echo ""
    echo "  Install from the App Store or:"
    echo "    xcode-select --install"
    echo ""
    echo "  agent-sim controls iOS Simulators, which require Xcode."
    failed=1
  elif ! xcrun simctl help &>/dev/null; then
    red "xcrun simctl not working — Xcode may be incomplete."
    echo "  Ensure you have a full Xcode install (not just Command Line Tools)."
    failed=1
  else
    dim "  Xcode: $(xcode-select -p)"
  fi

  # Simulator runtime
  if command -v xcrun &>/dev/null; then
    local runtimes
    runtimes="$(xcrun simctl list runtimes -j 2>/dev/null | grep -c '"identifier"' || echo 0)"
    if [[ "$runtimes" -eq 0 ]]; then
      red "No iOS Simulator runtimes installed."
      echo ""
      echo "  Open Xcode > Settings > Platforms > download an iOS runtime."
      failed=1
    else
      dim "  Simulator runtimes: $runtimes"
    fi
  fi

  if [[ "$failed" -eq 1 ]]; then
    echo ""
    red "Prerequisites not met. Fix the issues above and re-run."
    exit 1
  fi

  green "Prerequisites OK"
}

# --- Version Check ---
check_existing() {
  if command -v agent-sim &>/dev/null; then
    local current
    current="$(agent-sim --version 2>/dev/null || echo 'unknown')"
    dim "  Existing installation: $current"

    if [[ "$FORCE" != "1" && "$VERSION" != "latest" && "$current" == *"$VERSION"* ]]; then
      green "Already at $VERSION. Set AGENT_SIM_FORCE=1 to reinstall."
      exit 0
    fi
  fi
}

# --- Download ---
download() {
  local url

  if [[ -n "$DOWNLOAD_URL_OVERRIDE" ]]; then
    url="$DOWNLOAD_URL_OVERRIDE"
  elif [[ "$VERSION" == "latest" ]]; then
    url="https://github.com/$REPO/releases/latest/download/agent-sim-macos-arm64.tar.gz"
  else
    url="https://github.com/$REPO/releases/download/$VERSION/agent-sim-macos-arm64.tar.gz"
  fi

  echo "Downloading agent-sim..."
  dim "  $url"

  local tmp
  tmp="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf '$tmp'" EXIT

  if ! curl -fsSL "$url" -o "$tmp/agent-sim.tar.gz"; then
    fail "Download failed. Check the URL and your network connection."
  fi

  tar -xzf "$tmp/agent-sim.tar.gz" -C "$tmp"

  # Verify the binary works before replacing anything
  if [[ -f "$tmp/agent-sim/agent-sim" ]]; then
    if ! "$tmp/agent-sim/agent-sim" --version &>/dev/null && ! "$tmp/agent-sim/agent-sim" --help &>/dev/null; then
      fail "Downloaded binary failed verification."
    fi
  else
    fail "Expected binary not found in archive."
  fi

  # Install (no sudo — installs to ~/.local)
  echo "Installing to $INSTALL_DIR..."
  mkdir -p "$(dirname "$INSTALL_DIR")"
  mkdir -p "$BIN_DIR"
  rm -rf "$INSTALL_DIR"
  mv "$tmp/agent-sim" "$INSTALL_DIR"
  ln -sf "$INSTALL_DIR/agent-sim" "$BIN_LINK"

  green "Installed agent-sim to $INSTALL_DIR"
}

# --- AI Asset Registration ---
register_claude_plugin() {
  if [[ "$REGISTER_CLAUDE" != "1" ]]; then
    dim "  Claude plugin registration disabled (AGENT_SIM_REGISTER_CLAUDE=0)."
    return
  fi

  if [[ "$SCOPE" != "user" ]]; then
    dim "  Claude plugin registration is only applied for user scope."
    return
  fi

  local claude_settings="$HOME/.claude/settings.json"
  local plugin_path="$INSTALL_DIR"

  if [[ ! -d "$INSTALL_DIR/.claude-plugin" ]]; then
    dim "  No .claude-plugin in install; skipping Claude Code plugin registration."
    return
  fi

  mkdir -p "$HOME/.claude"

  if [[ ! -f "$claude_settings" ]]; then
    cat > "$claude_settings" <<SETTINGSEOF
{
  "plugins": [
    "$plugin_path"
  ]
}
SETTINGSEOF
    green "Registered agent-sim plugin with Claude Code"
    return
  fi

  if grep -q "\"$plugin_path\"" "$claude_settings" 2>/dev/null; then
    dim "  Claude Code plugin already registered."
    return
  fi

  if command -v python3 &>/dev/null; then
    python3 - "$claude_settings" "$plugin_path" <<'PY'
import json
import sys

settings_path = sys.argv[1]
plugin_path = sys.argv[2]

with open(settings_path, "r", encoding="utf-8") as file:
    settings = json.load(file)

plugins = settings.get("plugins", [])
if plugin_path not in plugins:
    plugins.append(plugin_path)
settings["plugins"] = plugins

with open(settings_path, "w", encoding="utf-8") as file:
    json.dump(settings, file, indent=2)
    file.write("\n")
PY
    green "Registered agent-sim plugin with Claude Code"
  else
    dim "  Could not auto-register plugin. Add manually to $claude_settings:"
    echo "    \"plugins\": [\"$plugin_path\"]"
  fi
}

install_claude_assets() {
  local root=""
  if [[ "$SCOPE" == "user" ]]; then
    root="$HOME/.claude"
  elif [[ "$SCOPE" == "project" ]]; then
    root="$PROJECT_DIR/.claude"
  else
    return
  fi

  mkdir -p "$root"
  copy_skill_dirs "$INSTALL_DIR/skills" "$root/skills"
}

install_opencode_assets() {
  if [[ "$REGISTER_OPENCODE" != "1" ]]; then
    dim "  OpenCode asset registration disabled (AGENT_SIM_REGISTER_OPENCODE=0)."
    return
  fi

  local root=""
  if [[ "$SCOPE" == "user" ]]; then
    root="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
  elif [[ "$SCOPE" == "project" ]]; then
    root="$PROJECT_DIR/.opencode"
  else
    return
  fi

  mkdir -p "$root"
  copy_skill_dirs "$INSTALL_DIR/skills" "$root/skills"
  copy_opencode_commands "$INSTALL_DIR/commands" "$root/commands"

  green "Registered agent-sim assets with OpenCode ($SCOPE scope)"
}

# --- Verify ---
verify() {
  if [[ ! -x "$BIN_LINK" ]]; then
    fail "Installation failed — $BIN_LINK is missing or not executable."
  fi

  if ! command -v agent-sim &>/dev/null; then
    if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
      echo ""
      red "agent-sim installed but $BIN_DIR is not on your PATH."
      echo ""
      echo "  Add to your shell profile:"
      echo "    export PATH=\"$BIN_DIR:\$PATH\""
      echo ""
      echo "  Then restart your shell or run:"
      echo "    source ~/.zshrc"
      return
    fi

    fail "Installation failed — agent-sim not found on PATH."
  fi

  echo ""
  agent-sim --version 2>/dev/null || agent-sim --help 2>&1 | head -1
  echo ""
  green "Ready. Run: agent-sim boot"
}

# --- Main ---
bold "agent-sim installer"
echo ""
resolve_scope
dim "  Asset scope: $SCOPE"
if [[ "$SCOPE" == "project" ]]; then
  dim "  Project dir: $PROJECT_DIR"
fi
echo ""
check_prerequisites
echo ""
check_existing
echo ""
download
echo ""
install_claude_assets
echo ""
register_claude_plugin
echo ""
install_opencode_assets
echo ""
verify
