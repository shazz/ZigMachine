"""Shared helpers for the ZigMachine documentation generators.

Two pages are generated from this package:

  tools/gen_docs.py      -> docs/ZIGMACHINE_GUIDE.html  (the reference)
  tools/gen_tutorial.py  -> docs/TUTORIAL.html          (the teaching page)

They were one 373-line script until the tutorial grew its own page; the split
keeps every module inside the project's 200-line ceiling and lets the tutorial
reuse the guide's Zig parsers for its register callouts.
"""
from __future__ import annotations

import html
import posixpath
import re
from pathlib import Path

import markdown  # renders the repo's .md prose into both pages

ROOT = Path(__file__).resolve().parents[2]
BLOB = "https://github.com/shazz/ZigMachine/blob/main/"
MD_HREF = re.compile(r'href="(?![a-zA-Z][a-zA-Z0-9+.-]*:|#|/)([^"#?]+\.md)((?:#[^"]*)?)"')


def esc(s: str) -> str:
    return html.escape(s)


def render_markdown(text: str) -> str:
    """Render markdown source to HTML with the extensions both pages rely on."""
    return markdown.markdown(text, extensions=["fenced_code", "tables"])


def blob_links(markup: str, src_rel: str) -> str:
    """Point the .md links of markup rendered from repo file `src_rel` at GitHub.

    The pages are served from a directory that holds no .md (site/, phase 3 of the repo
    reorganisation), so a relative ZIGOS_API.md link would 404 there.
    """
    base = posixpath.dirname(src_rel)

    def repl(m: re.Match[str]) -> str:
        return f'href="{BLOB}{posixpath.normpath(posixpath.join(base, m.group(1)))}{m.group(2)}"'

    return MD_HREF.sub(repl, markup)


def render_markdown_file(rel: str) -> str:
    """Render a repo markdown file to HTML (fenced code + tables) for a page section."""
    return blob_links(render_markdown((ROOT / rel).read_text()), rel)


STAMP_RE = re.compile(r"(\.(?:js|css))\?v=[0-9a-f]+")


def unstamped(text: str) -> str:
    """The page minus cache_bust.py's ?v= hashes, which it rewrites after generation."""
    return STAMP_RE.sub(r"\1", text)
