#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$SCRIPT_DIR/.."
DIST="$ROOT/dist/agent-sim"
TARBALL="$ROOT/dist/agent-sim-macos-arm64.tar.gz"

echo "Building release..."
cd "$ROOT"
swift build -c release 2>&1

echo "Packaging..."
rm -rf "$DIST" "$TARBALL"
mkdir -p "$DIST"

# Copy binary
cp .build/release/AgentSim "$DIST/agent-sim"

# Copy dynamic frameworks (just the .framework dirs, not the xcframework wrappers)
for fw in FBControlCore FBSimulatorControl FBDeviceControl XCTestBootstrap; do
  cp -R "Frameworks/${fw}.xcframework/macos-arm64/${fw}.framework" "$DIST/"
done

# Copy non-binary assets
cp -R "$ROOT/commands" "$DIST/"
cp -R "$ROOT/skills" "$DIST/"
cp -R "$ROOT/Templates" "$DIST/"
cp -R "$ROOT/references" "$DIST/"

# Copy Claude Code plugin manifest
cp -R "$ROOT/.claude-plugin" "$DIST/"

# Strip debug symbols for smaller size
strip -x "$DIST/agent-sim" 2>/dev/null || true

# Ad-hoc codesign everything (required on Apple Silicon)
for fw in FBControlCore FBSimulatorControl FBDeviceControl XCTestBootstrap; do
  codesign --force --sign - "$DIST/${fw}.framework" 2>/dev/null || true
done
codesign --force --sign - "$DIST/agent-sim" 2>/dev/null || true

# Create tarball for GitHub releases
cd "$ROOT/dist"
tar -czf agent-sim-macos-arm64.tar.gz agent-sim/

# Show result
echo ""
echo "Distribution:"
ls -lh "$DIST/agent-sim"
du -sh "$DIST"
echo ""
echo "Tarball:"
ls -lh "$TARBALL"
echo ""
echo "Upload to GitHub release:"
echo "  gh release create v0.1.0 $TARBALL --title 'v0.1.0' --notes 'Initial release'"
echo ""
echo "Users install with:"
echo "  curl -fsSL https://raw.githubusercontent.com/pproenca/agent-sim/main/scripts/install.sh | bash"
