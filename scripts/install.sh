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

# --- Colors ---
red()   { printf "\033[31m%s\033[0m\n" "$1"; }
green() { printf "\033[32m%s\033[0m\n" "$1"; }
dim()   { printf "\033[2m%s\033[0m\n" "$1"; }
bold()  { printf "\033[1m%s\033[0m\n" "$1"; }

# --- Prerequisites ---
check_prerequisites() {
  local failed=0

  # macOS
  if [[ "$(uname)" != "Darwin" ]]; then
    red "agent-sim requires macOS."
    exit 1
  fi

  # Apple Silicon
  if [[ "$(uname -m)" != "arm64" ]]; then
    red "agent-sim requires Apple Silicon (arm64). Intel Macs are not supported."
    exit 1
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

  if [[ "$VERSION" == "latest" ]]; then
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
    red "Download failed."
    echo "  Check the URL and your network connection."
    exit 1
  fi

  tar -xzf "$tmp/agent-sim.tar.gz" -C "$tmp"

  # Verify the binary works before replacing anything
  if [[ -f "$tmp/agent-sim/agent-sim" ]]; then
    if ! "$tmp/agent-sim/agent-sim" --version &>/dev/null && ! "$tmp/agent-sim/agent-sim" --help &>/dev/null; then
      red "Downloaded binary failed verification."
      exit 1
    fi
  else
    red "Expected binary not found in archive."
    exit 1
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

# --- Verify ---
verify() {
  if ! command -v agent-sim &>/dev/null; then
    # Check if ~/.local/bin is on PATH
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

    red "Installation failed — agent-sim not found on PATH."
    exit 1
  fi

  echo ""
  agent-sim --version 2>/dev/null || agent-sim --help 2>&1 | head -1
  echo ""
  green "Ready. Run: agent-sim boot"
}

# --- Main ---
bold "agent-sim installer"
echo ""
check_prerequisites
echo ""
check_existing
echo ""
download
echo ""
verify
