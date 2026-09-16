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
