#!/usr/bin/env python3
"""
Apple Documentation Scraper
Converts Apple developer documentation to skill-ready markdown.

Usage:
  python scrape_apple_docs.py <url> [url2 ...]
  python scrape_apple_docs.py --list urls.txt
  python scrape_apple_docs.py --crawl --depth 2 <url>

Apple exposes a public DocC JSON API at:
  https://developer.apple.com/tutorials/data/documentation/{path}.json
No authentication or third-party dependencies required.
"""

import json
import sys
import time
import argparse
from pathlib import Path
from urllib.parse import urlparse
from urllib.request import urlopen, Request
from urllib.error import HTTPError, URLError

BASE_JSON = "https://developer.apple.com/tutorials/data"
UA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36"


# ── Fetch ─────────────────────────────────────────────────────────────────────


def url_to_json(url: str) -> str:
    """https://developer.apple.com/documentation/foo/bar → …/tutorials/data/documentation/foo/bar.json"""
    path = urlparse(url).path.rstrip("/")
    return f"{BASE_JSON}{path}.json"


def fetch(url: str) -> dict:
    req = Request(url, headers={"User-Agent": UA})
    with urlopen(req, timeout=20) as resp:
        return json.loads(resp.read().decode())


# ── Inline renderer ───────────────────────────────────────────────────────────


def inline(items: list, refs: dict) -> str:
    parts = []
    for item in items:
        t = item.get("type", "")
        if t == "text":
            parts.append(item.get("text", ""))
        elif t == "codeVoice":
            parts.append(f"`{item.get('code', '')}`")
        elif t in ("emphasis", "newTerm"):
            parts.append(f"*{inline(item.get('inlineContent', []), refs)}*")
        elif t == "strong":
            parts.append(f"**{inline(item.get('inlineContent', []), refs)}**")
        elif t == "inlineHead":
            parts.append(f"**{inline(item.get('inlineContent', []), refs)}**")
        elif t == "reference":
            ident = item.get("identifier", "")
            ref = refs.get(ident, {})
            title = ref.get("title") or ident.split("/")[-1]
            doc_url = ref.get("url", "")
            if doc_url:
                parts.append(f"[{title}](https://developer.apple.com{doc_url})")
            else:
                parts.append(title)
        elif t == "image":
            ident = item.get("identifier", "")
            ref = refs.get(ident, {})
            alt = ref.get("alt") or ident
            parts.append(f"[image: {alt}]")
    return "".join(parts)


# ── Block renderer ────────────────────────────────────────────────────────────


def block(items: list, refs: dict, indent: str = "") -> list[str]:
    lines = []
    for item in items:
        t = item.get("type", "")

        if t == "heading":
            hashes = "#" * (item.get("level", 2) + 1)
            lines += [f"{hashes} {item.get('text', '')}", ""]

        elif t == "paragraph":
            text = inline(item.get("inlineContent", []), refs)
            if text.strip():
                lines += [f"{indent}{text}", ""]

        elif t == "codeListing":
            lang = item.get("syntax", "")
            code = "\n".join(item.get("code", []))
            lines += [f"```{lang}", code, "```", ""]

        elif t == "unorderedList":
            for li in item.get("items", []):
                sub = block(li.get("content", []), refs, indent=indent + "  ")
                if sub:
                    first = sub[0].strip()
                    rest = sub[1:]
                    lines.append(f"{indent}- {first}")
                    lines.extend(rest)
                else:
                    lines.append(f"{indent}- ")
            lines.append("")

        elif t == "orderedList":
            for i, li in enumerate(item.get("items", []), 1):
                sub = block(li.get("content", []), refs, indent=indent + "  ")
                if sub:
                    first = sub[0].strip()
                    rest = sub[1:]
                    lines.append(f"{indent}{i}. {first}")
                    lines.extend(rest)
                else:
                    lines.append(f"{indent}{i}. ")
            lines.append("")

        elif t == "termList":
            for entry in item.get("items", []):
                term_text = inline(entry.get("term", {}).get("inlineContent", []), refs)
                defn_lines = block(entry.get("definition", {}).get("content", []), refs)
                defn = " ".join(ln for ln in defn_lines if ln.strip())
                lines += [f"{indent}**{term_text}**", f"{indent}  {defn}", ""]

        elif t == "aside":
            style = item.get("style", "Note").capitalize()
            content_lines = block(item.get("content", []), refs)
            body = " ".join(ln for ln in content_lines if ln.strip())
            lines += [f"> **{style}:** {body}", ""]

        elif t == "table":
            rows = item.get("rows", [])
            if rows:
                def cell_text(cell) -> str:
                    content = cell if isinstance(cell, list) else cell.get("content", [])
                    rendered = block(content, refs)
                    return " ".join(ln for ln in rendered if ln.strip())

                header_cells = [cell_text(c) for c in rows[0]]
                lines.append("| " + " | ".join(header_cells) + " |")
                lines.append("| " + " | ".join("---" for _ in header_cells) + " |")
                for row in rows[1:]:
                    cells = [cell_text(c) for c in row]
                    lines.append("| " + " | ".join(cells) + " |")
                lines.append("")

    return lines


# ── Converter ─────────────────────────────────────────────────────────────────


def to_markdown(data: dict, source_url: str) -> str:
    refs = data.get("references", {})
    meta = data.get("metadata", {})
    title = meta.get("title", "Untitled")
    role = meta.get("roleHeading", "")

    out = [f"# {title}", ""]
    if role:
        out += [f"_{role}_", ""]
    out += [f"> Source: {source_url}", ""]

    # Abstract / summary
    abstract_items = data.get("abstract", [])
    if abstract_items:
        text = inline(abstract_items, refs)
        if text.strip():
            out += [text, ""]

    # Main content
    for section in data.get("primaryContentSections", []):
        kind = section.get("kind", "")

        if kind == "content":
            out.extend(block(section.get("content", []), refs))

        elif kind == "declarations":
            for decl in section.get("declarations", []):
                tokens = decl.get("tokens", [])
                code = "".join(t.get("text", "") for t in tokens)
                out += ["```swift", code, "```", ""]

        elif kind == "parameters":
            params = section.get("parameters", [])
            if params:
                out += ["## Parameters", ""]
                for p in params:
                    name = p.get("name", "")
                    desc_lines = block(p.get("content", []), refs)
                    desc = " ".join(ln for ln in desc_lines if ln.strip())
                    out.append(f"- **`{name}`**: {desc}")
                out.append("")

        elif kind == "restParameters":
            items = section.get("items", [])
            if items:
                out += ["## Parameters", ""]
                for p in items:
                    name = p.get("name", "")
                    desc_lines = block(p.get("content", []), refs)
                    desc = " ".join(ln for ln in desc_lines if ln.strip())
                    out.append(f"- **`{name}`**: {desc}")
                out.append("")

    return "\n".join(out)


# ── Crawler helpers ───────────────────────────────────────────────────────────


_DOC_PREFIXES = ("/documentation/", "/design/")
_STRIP_SEGMENTS = {"documentation", "human-interface-guidelines"}


def child_urls(data: dict) -> list[str]:
    """Collect child page URLs for --crawl mode."""
    refs = data.get("references", {})
    seen: set[str] = set()
    urls: list[str] = []

    for section in data.get("topicSections", []):
        for ident in section.get("identifiers", []):
            ref = refs.get(ident, {})
            if not isinstance(ref, dict):
                continue
            path = ref.get("url", "")
            if any(path.startswith(p) for p in _DOC_PREFIXES) and path not in seen:
                seen.add(path)
                urls.append(f"https://developer.apple.com{path}")

    return urls


def path_to_filename(url: str) -> str:
    parts = [p for p in urlparse(url).path.split("/") if p and p not in _STRIP_SEGMENTS]
    return ("-".join(parts) or "index") + ".md"


# ── Scrape one URL ────────────────────────────────────────────────────────────


def scrape_one(url: str, output_dir: Path, delay: float, skip_existing: bool = False) -> dict | None:
    out_path = output_dir / path_to_filename(url)

    if skip_existing and out_path.exists():
        print(f"  – skip (exists): {out_path.name}")
        try:
            return fetch(url_to_json(url))
        except Exception:
            return None

    json_url = url_to_json(url)
    try:
        data = fetch(json_url)
    except HTTPError as e:
        print(f"  HTTP {e.code}: {json_url}")
        return None
    except URLError as e:
        print(f"  Network error: {e.reason}")
        return None

    md = to_markdown(data, url)
    out_path.write_text(md, encoding="utf-8")
    print(f"  ✓ {out_path.name}")

    time.sleep(delay)
    return data


# ── CLI ───────────────────────────────────────────────────────────────────────


def main():
    parser = argparse.ArgumentParser(
        description="Scrape Apple developer documentation to skill-ready markdown.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Single page
  python scrape_apple_docs.py https://developer.apple.com/design/human-interface-guidelines/designing-for-ios

  # Crawl the full iOS HIG (2 levels deep)
  python scrape_apple_docs.py --crawl --depth 2 --list hig-urls.txt

  # Resume an interrupted scrape
  python scrape_apple_docs.py --crawl --depth 2 --skip-existing --list hig-urls.txt
""",
    )
    parser.add_argument("urls", nargs="*", help="Apple documentation URL(s) to scrape")
    parser.add_argument("--list", "-l", metavar="FILE",
                        help="File with one URL per line (# comments ignored)")
    parser.add_argument("--crawl", action="store_true",
                        help="Also scrape child pages from topicSections")
    parser.add_argument("--depth", type=int, default=1, metavar="N",
                        help="Max crawl depth (default: 1, only meaningful with --crawl)")
    parser.add_argument("--output", "-o", default="./references/hig", metavar="DIR",
                        help="Output directory (default: ./references/hig)")
    parser.add_argument("--delay", type=float, default=0.5, metavar="SEC",
                        help="Delay between requests in seconds (default: 0.5)")
    parser.add_argument("--skip-existing", action="store_true",
                        help="Skip URLs whose output file already exists (useful for resuming)")
    args = parser.parse_args()

    urls = list(args.urls)
    if args.list:
        list_path = Path(args.list)
        if not list_path.is_absolute():
            list_path = Path(__file__).parent / list_path
        with open(list_path) as f:
            urls.extend(ln.strip() for ln in f if ln.strip() and not ln.startswith("#"))

    if not urls:
        parser.print_help()
        sys.exit(1)

    output_dir = Path(args.output)
    if not output_dir.is_absolute():
        output_dir = Path(__file__).resolve().parent.parent / output_dir
    output_dir.mkdir(parents=True, exist_ok=True)
    print(f"Output → {output_dir.resolve()}\n")

    visited: set[str] = set()
    queue: list[tuple[str, int]] = [(u, 0) for u in urls]
    failed: list[str] = []

    while queue:
        url, depth = queue.pop(0)
        if url in visited:
            continue
        visited.add(url)
        print(f"[depth={depth}] {url}")

        data = scrape_one(url, output_dir, args.delay, skip_existing=args.skip_existing)
        if data is None:
            failed.append(url)
            continue

        if args.crawl and depth < args.depth:
            for child in child_urls(data):
                if child not in visited:
                    queue.append((child, depth + 1))

    ok = len(visited) - len(failed)
    print(f"\nDone: {ok}/{len(visited)} scraped → {output_dir.resolve()}")
    if failed:
        print("\nFailed:")
        for u in failed:
            print(f"  {u}")


if __name__ == "__main__":
    main()
