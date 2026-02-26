#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$SCRIPT_DIR/.."
DIST_ROOT="$ROOT/dist"
DIST="$DIST_ROOT/agent-sim"
TARBALL="$DIST_ROOT/agent-sim-macos-arm64.tar.gz"
BINARY_PATH="$ROOT/.build/release/AgentSim"
FRAMEWORKS=(FBControlCore FBSimulatorControl FBDeviceControl XCTestBootstrap)
ASSET_DIRS=(commands skills Templates references .claude-plugin)

fail() {
  echo "Error: $1" >&2
  exit 1
}

require_path() {
  local path="$1"
  [[ -e "$path" ]] || fail "required path not found: $path"
}

build_release_binary() {
  echo "Building release binary..."
  cd "$ROOT"
  swift build -c release
  require_path "$BINARY_PATH"
}

prepare_dist() {
  echo "Preparing dist directory..."
  rm -rf "$DIST" "$TARBALL"
  mkdir -p "$DIST"
}

copy_binary_and_frameworks() {
  cp "$BINARY_PATH" "$DIST/agent-sim"

  for fw in "${FRAMEWORKS[@]}"; do
    local framework_path="$ROOT/Frameworks/${fw}.xcframework/macos-arm64/${fw}.framework"
    require_path "$framework_path"
    cp -R "$framework_path" "$DIST/"
  done
}

copy_assets() {
  for dir in "${ASSET_DIRS[@]}"; do
    local source="$ROOT/$dir"
    require_path "$source"
    cp -R "$source" "$DIST/"
  done
}

sign_payload() {
  strip -x "$DIST/agent-sim" 2>/dev/null || true

  for fw in "${FRAMEWORKS[@]}"; do
    codesign --force --sign - "$DIST/${fw}.framework" 2>/dev/null || true
  done
  codesign --force --sign - "$DIST/agent-sim" 2>/dev/null || true
}

create_tarball() {
  echo "Creating release tarball..."
  cd "$DIST_ROOT"
  tar -czf "$(basename "$TARBALL")" "$(basename "$DIST")"
  require_path "$TARBALL"
}

print_summary() {
  echo ""
  echo "Distribution:"
  ls -lh "$DIST/agent-sim"
  du -sh "$DIST"
  echo ""
  echo "Tarball:"
  ls -lh "$TARBALL"
}

build_release_binary
prepare_dist
copy_binary_and_frameworks
copy_assets
sign_payload
create_tarball
print_summary
