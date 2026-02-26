#!/bin/bash
set -euo pipefail

# Scrape Apple's Human Interface Guidelines for agent-sim UI critique
# Usage: ./scripts/scrape-hig.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$SCRIPT_DIR/.."

echo "Scraping Apple Human Interface Guidelines..."
echo "This crawls ~200 pages with 0.5s delay (~2 min)"
echo ""

python3 "$SCRIPT_DIR/scrape_apple_docs.py" \
  --crawl \
  --depth 2 \
  --list "$SCRIPT_DIR/hig-urls.txt" \
  --output "$ROOT/references/hig" \
  --skip-existing

echo ""
echo "Reference docs ready at: $ROOT/references/hig/"
echo "Total files: $(ls "$ROOT/references/hig/"*.md 2>/dev/null | wc -l | tr -d ' ')"
