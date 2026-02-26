#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$SCRIPT_DIR/.."
TARBALL="$ROOT/dist/agent-sim-macos-arm64.tar.gz"
TMP_DIR="$(mktemp -d)"
KEEP_TMP="${AGENT_SIM_KEEP_TMP:-0}"

cleanup() {
  if [[ "$KEEP_TMP" == "1" ]]; then
    echo "Keeping temp files: $TMP_DIR"
    return
  fi
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

step() {
  echo ""
  echo "==> $1"
}

fail() {
  echo "Error: $1" >&2
  exit 1
}

require_file() {
  [[ -f "$1" ]] || fail "missing file: $1"
}

require_dir() {
  [[ -d "$1" ]] || fail "missing directory: $1"
}

assert_tar_contains() {
  local pattern="$1"
  if ! tar -tzf "$TARBALL" | grep -q "$pattern"; then
    fail "tarball missing expected entry: $pattern"
  fi
}

verify_packaging() {
  step "Build and package release payload"
  bash "$SCRIPT_DIR/package.sh"

  require_file "$TARBALL"
  assert_tar_contains '^agent-sim/agent-sim$'
  assert_tar_contains '^agent-sim/commands/'
  assert_tar_contains '^agent-sim/skills/'
  assert_tar_contains '^agent-sim/Templates/'
  assert_tar_contains '^agent-sim/references/'
  assert_tar_contains '^agent-sim/.claude-plugin/'
}

verify_install_flow() {
  step "Run installer smoke test (project scope, isolated HOME)"

  local test_home="$TMP_DIR/home"
  local project_dir="$TMP_DIR/project"
  local test_install="$test_home/.local/lib/agent-sim"
  local test_bin="$test_home/.local/bin"

  mkdir -p "$test_home" "$project_dir"

  HOME="$test_home" \
  AGENT_SIM_SKIP_PREREQS=1 \
  AGENT_SIM_URL="file://$TARBALL" \
  AGENT_SIM_SCOPE=project \
  AGENT_SIM_PROJECT_DIR="$project_dir" \
  AGENT_SIM_DIR="$test_install" \
  AGENT_SIM_BIN="$test_bin" \
  bash "$SCRIPT_DIR/install.sh"

  require_file "$test_bin/agent-sim"
  "$test_bin/agent-sim" --version >/dev/null 2>&1 || "$test_bin/agent-sim" --help >/dev/null

  require_dir "$project_dir/.claude/skills/agent-sim"
  require_dir "$project_dir/.claude/skills/agentsim-new"
  require_dir "$project_dir/.opencode/skills/agent-sim"
  require_dir "$project_dir/.opencode/skills/agentsim-replay"
  require_file "$project_dir/.opencode/commands/agentsim-new.md"
  require_file "$project_dir/.opencode/commands/agentsim-tests.md"
}

verify_release_dry_run() {
  step "Run release script dry-run smoke test"
  bash "$SCRIPT_DIR/release.sh" patch --dry-run --skip-formula >/dev/null
}

verify_packaging
verify_install_flow
verify_release_dry_run

echo ""
echo "All workflow checks passed."
