#!/bin/bash
set -euo pipefail

# agent-sim release script
# Usage: ./scripts/release.sh [major|minor|patch] [--dry-run] [--skip-formula]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$SCRIPT_DIR/.."
REPO="pproenca/agent-sim"
TAP_REPO="pproenca/homebrew-tap"
FORMULA_PATH="Formula/agent-sim.rb"
PLUGIN_JSON="$ROOT/.claude-plugin/plugin.json"
AGENT_SIM_SWIFT="$ROOT/Sources/AgentSim/AgentSim.swift"
TARBALL="$ROOT/dist/agent-sim-macos-arm64.tar.gz"

usage() {
  echo "Usage: $0 [major|minor|patch] [--dry-run] [--skip-formula]"
}

fail() {
  echo "Error: $1" >&2
  exit 1
}

decode_base64() {
  if base64 -d </dev/null >/dev/null 2>&1; then
    base64 -d
  else
    base64 -D
  fi
}

require_clean_tree() {
  if ! git diff --quiet || ! git diff --cached --quiet; then
    fail "working tree is dirty. Commit or stash changes first."
  fi
}

sync_versions() {
  local new_version="$1"
  local new_tag="$2"
  local tracked_files=()

  if [[ -f "$PLUGIN_JSON" ]]; then
    sed -i '' -E "s/\"version\": *\"[^\"]+\"/\"version\": \"${new_version}\"/" "$PLUGIN_JSON"
    tracked_files+=("$PLUGIN_JSON")
  fi
  if [[ -f "$AGENT_SIM_SWIFT" ]]; then
    sed -i '' -E "s/version: \"[^\"]+\"/version: \"${new_version}\"/" "$AGENT_SIM_SWIFT"
    tracked_files+=("$AGENT_SIM_SWIFT")
  fi

  if [[ "${#tracked_files[@]}" -eq 0 ]]; then
    return
  fi

  if ! git diff --quiet -- "${tracked_files[@]}"; then
    git add -- "${tracked_files[@]}"
    git commit -m "Sync version to ${new_tag}"
  fi
}

update_homebrew_formula() {
  local new_tag="$1"
  local new_version="$2"
  local sha256="$3"
  local dry_run="$4"

  local current_formula
  local current_sha
  local updated_formula

  current_formula="$(gh api "repos/${TAP_REPO}/contents/${FORMULA_PATH}" --jq '.content' | decode_base64)"
  current_sha="$(gh api "repos/${TAP_REPO}/contents/${FORMULA_PATH}" --jq '.sha')"

  updated_formula="$(echo "$current_formula" \
    | sed -E "s|url \"https://github.com/${REPO}/releases/download/v[^\"]+/|url \"https://github.com/${REPO}/releases/download/${new_tag}/|" \
    | sed -E "s|sha256 \"[a-f0-9]+\"|sha256 \"${sha256}\"|" \
    | sed -E "s|version \"[^\"]+\"|version \"${new_version}\"|")"

  if [[ "$dry_run" -eq 1 ]]; then
    echo "Dry run: would update ${TAP_REPO}/${FORMULA_PATH}"
    echo "$updated_formula" | sed -n '1,20p'
    return
  fi

  echo "$updated_formula" | gh api "repos/${TAP_REPO}/contents/${FORMULA_PATH}" \
    --method PUT \
    --field message="Update agent-sim to ${new_tag}" \
    --field sha="$current_sha" \
    --raw-field content="$(echo "$updated_formula" | base64 | tr -d '\n')" \
    --silent
}

BUMP=""
DRY_RUN=0
SKIP_FORMULA=0

for arg in "$@"; do
  case "$arg" in
    major|minor|patch)
      if [[ -n "$BUMP" ]]; then
        usage
        fail "multiple bump arguments provided"
      fi
      BUMP="$arg"
      ;;
    --dry-run)
      DRY_RUN=1
      ;;
    --skip-formula)
      SKIP_FORMULA=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      fail "unknown argument: $arg"
      ;;
  esac
done

if [[ -z "$BUMP" ]]; then
  usage
  exit 1
fi

cd "$ROOT"

CURRENT_BRANCH="$(git branch --show-current)"
if [[ "$DRY_RUN" -eq 0 && "$CURRENT_BRANCH" != "master" ]]; then
  fail "releases must be cut from master (current: ${CURRENT_BRANCH})"
fi

if [[ "$DRY_RUN" -eq 0 ]]; then
  require_clean_tree
fi

LATEST_TAG="$(git describe --tags --abbrev=0 2>/dev/null || echo "v0.0.0")"
CURRENT="${LATEST_TAG#v}"
IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"

case "$BUMP" in
  major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
  minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
  patch) PATCH=$((PATCH + 1)) ;;
esac

NEW_VERSION="${MAJOR}.${MINOR}.${PATCH}"
NEW_TAG="v${NEW_VERSION}"

if git rev-parse "$NEW_TAG" >/dev/null 2>&1; then
  fail "tag ${NEW_TAG} already exists"
fi

echo "Releasing: ${LATEST_TAG} → ${NEW_TAG} (${BUMP})"
echo ""

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "Dry run: skipping version file updates and commit."
else
  sync_versions "$NEW_VERSION" "$NEW_TAG"
  require_clean_tree
fi

echo "Building release..."
"$SCRIPT_DIR/package.sh"

if [[ ! -f "$TARBALL" ]]; then
  fail "tarball not found at $TARBALL"
fi

SHA256="$(shasum -a 256 "$TARBALL" | awk '{print $1}')"
echo "SHA256: $SHA256"
echo ""

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "Dry run: skipping tag push and GitHub release creation."
  if [[ "$SKIP_FORMULA" -eq 1 ]]; then
    echo "Dry run: skipping Homebrew formula update validation."
  else
    echo "Dry run: validating Homebrew formula update payload..."
    update_homebrew_formula "$NEW_TAG" "$NEW_VERSION" "$SHA256" 1
  fi
  echo ""
  echo "Dry run complete."
  exit 0
fi

echo "Tagging ${NEW_TAG}..."
git tag -a "$NEW_TAG" -m "Release ${NEW_TAG}"
git push origin master --tags

echo "Creating GitHub release ${NEW_TAG}..."
gh release create "$NEW_TAG" "$TARBALL" \
  --repo "$REPO" \
  --title "$NEW_TAG" \
  --generate-notes

if [[ "$SKIP_FORMULA" -eq 1 ]]; then
  echo "Skipping Homebrew formula update."
else
  echo "Updating Homebrew formula in ${TAP_REPO}..."
  update_homebrew_formula "$NEW_TAG" "$NEW_VERSION" "$SHA256" 0
fi

echo ""
echo "Done! Released ${NEW_TAG}"
echo "  GitHub: https://github.com/${REPO}/releases/tag/${NEW_TAG}"
echo "  Brew:   brew upgrade agent-sim"
