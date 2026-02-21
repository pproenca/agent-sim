#!/bin/bash
set -euo pipefail

# agent-sim installer
# Usage: curl -fsSL https://raw.githubusercontent.com/pproenca/agent-sim/master/scripts/install.sh | bash

VERSION="${AGENT_SIM_VERSION:-latest}"
INSTALL_DIR="${AGENT_SIM_DIR:-/usr/local/lib/agent-sim}"
BIN_LINK="/usr/local/bin/agent-sim"
REPO="pproenca/agent-sim"

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

  # Xcode
  if ! xcode-select -p &>/dev/null; then
    red "Xcode is not installed."
    echo ""
    echo "  Install from the App Store or:"
    echo "    xcode-select --install"
    echo ""
    echo "  agent-sim controls iOS Simulators, which require Xcode."
    failed=1
  else
    local xcode_path
    xcode_path="$(xcode-select -p)"
    dim "  Xcode: $xcode_path"

    # Verify CoreSimulator exists
    local coresim="$xcode_path/../SharedFrameworks/CoreSimulator.framework"
    if [[ ! -d "$coresim" ]]; then
      red "CoreSimulator.framework not found at expected path."
      echo "  Expected: $coresim"
      echo "  Ensure you have a full Xcode install (not just Command Line Tools)."
      failed=1
    fi
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
  trap 'rm -rf "$tmp"' EXIT

  if ! curl -fsSL "$url" -o "$tmp/agent-sim.tar.gz"; then
    red "Download failed."
    echo "  Check the URL and your network connection."
    exit 1
  fi

  tar -xzf "$tmp/agent-sim.tar.gz" -C "$tmp"

  # Install
  echo "Installing to $INSTALL_DIR..."
  sudo rm -rf "$INSTALL_DIR"
  sudo mkdir -p "$INSTALL_DIR"
  sudo cp -R "$tmp/agent-sim/" "$INSTALL_DIR/"
  sudo ln -sf "$INSTALL_DIR/agent-sim" "$BIN_LINK"

  green "Installed agent-sim to $INSTALL_DIR"
}

# --- Verify ---
verify() {
  if ! command -v agent-sim &>/dev/null; then
    red "Installation failed — agent-sim not found on PATH."
    echo "  Ensure /usr/local/bin is on your PATH."
    exit 1
  fi

  echo ""
  agent-sim --version 2>/dev/null || agent-sim --help 2>&1 | head -1
  echo ""
  green "Ready. Boot a simulator and run: agent-sim status"
}

# --- Main ---
bold "agent-sim installer"
echo ""
check_prerequisites
echo ""
download
echo ""
verify
