#!/usr/bin/env python3
"""Stamp every local script/stylesheet in docs/*.html with a CONTENT hash.

WHY THIS EXISTS: GitHub Pages serves docs/ with a long cache lifetime, so a
browser keeps a page's scripts for hours. index.html used to carry hand-bumped
?v=36 numbers. #68 changed sealed-loader.js without bumping it, cached phones
kept the old loader (which cannot unpack disks), and every packed disk failed
with "module doesn't start with \\0asm". A number someone must remember to bump
WILL be forgotten.

So the version is derived: `?v=` becomes the first 8 hex digits of the sha256
of the referenced file. A file gets a new URL exactly when its bytes change, and
an unchanged one keeps its URL, so running this twice changes nothing.

build.sh runs it, so the pre-push hook's "docs/ matches the source" check
rejects a push whose loader or CSS changed without the rewritten HTML.

Usage: tools/cache_bust.py [--check]   (--check: list stale references, write nothing)
"""
import hashlib
import re
import sys
from pathlib import Path

DOCS = Path(__file__).resolve().parent.parent / "docs"
# A local src/href on a <script> or <link> tag: not a URL with a scheme, not
# protocol-relative, not an in-page anchor. Only .js and .css are versioned; the
# loader cache-busts the .wasm/.zmd it fetches itself (BUST in sealed-loader.js).
TAG = re.compile(r'(<(?:script|link)\b[^>]*?\b(?:src|href)=")([^"?#:]+\.(?:js|css))(\?v=[^"]*)?(")', re.I)


def short_hash(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()[:8]


def stamp(html: Path) -> tuple[str, list[str]]:
    """The page with every local asset reference stamped, and what changed."""
    text = html.read_text(encoding="utf-8")
    changes: list[str] = []

    def repl(m: re.Match) -> str:
        rel, old = m.group(2), m.group(3) or ""
        target = (html.parent / rel).resolve()
        if not target.is_file():
            sys.exit(f"cache_bust: {html.name} references {rel}, which does not exist")
        new = f"?v={short_hash(target)}"
        if old != new:
            changes.append(f"{html.name}: {rel}{old or ' (unversioned)'} -> {rel}{new}")
        return f"{m.group(1)}{rel}{new}{m.group(4)}"

    return TAG.sub(repl, text), changes


def main() -> int:
    check = "--check" in sys.argv[1:]
    stale: list[str] = []
    for html in sorted(DOCS.glob("*.html")):
        text, changes = stamp(html)
        stale += changes
        if changes and not check:
            html.write_text(text, encoding="utf-8")
    for line in stale:
        print(f"cache_bust: {line}")
    if check and stale:
        print("cache_bust: stale ?v= stamps (run tools/cache_bust.py)")
        return 1
    print(f"cache_bust: {'all stamps current' if not stale else f'{len(stale)} stamp(s) updated'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
