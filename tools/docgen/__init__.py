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
import re
from pathlib import Path

import markdown  # renders the repo's .md prose into both pages

ROOT = Path(__file__).resolve().parents[2]


def esc(s: str) -> str:
    return html.escape(s)


def render_markdown(text: str) -> str:
    """Render markdown source to HTML with the extensions both pages rely on."""
    return markdown.markdown(text, extensions=["fenced_code", "tables"])


def render_markdown_file(rel: str) -> str:
    """Render a repo markdown file to HTML (fenced code + tables) for a page section."""
    return render_markdown((ROOT / rel).read_text())


STAMP_RE = re.compile(r"(\.(?:js|css))\?v=[0-9a-f]+")


def unstamped(text: str) -> str:
    """The page minus cache_bust.py's ?v= hashes, which it rewrites after generation."""
    return STAMP_RE.sub(r"\1", text)
