"""Fix FILE-RELATIVE references when files move: markdown links, html src/href, JS imports.

A repo-rooted table cannot rewrite `../docs/wasm_hiwater.js` inside a harness that itself
moves one level down: the right answer depends on both ends. So each relative target is
resolved against the file's OLD directory to a repo path, that path is mapped through
the phase's moves, and the result is made relative again to the file's NEW directory.

Only targets that exist (a tracked file or directory, before the move) are touched, so
code in a markdown fence (`f[0](x)`) is left alone.
"""
from __future__ import annotations

import posixpath
import re
from collections.abc import Callable

SCHEME = re.compile(r"^(?:[a-zA-Z][a-zA-Z0-9+.-]*:|#|/|\?|\$|\{|<)")
MD = [re.compile(r"\]\(\s*<?([^()\s<>]+)>?(?=[\s)])"), re.compile(r"(?m)^\s*\[[^\]]+\]:\s*(\S+)"),
      re.compile(r"""\b(?:src|href)=["']([^"']+)["']""")]
HTML = [re.compile(r"""\b(?:src|href)=["']([^"']+)["']""")]
JS = [re.compile(r"""\bfrom\s*["']([^"']+)["']"""), re.compile(r"""\bimport\s*\(\s*["']([^"']+)["']"""),
      re.compile(r"""\bimport\s+["']([^"']+)["']"""),
      re.compile(r"""\bnew URL\(\s*["']([^"']+)["']\s*,\s*import\.meta\.url""")]


def patterns_for(path: str) -> tuple[list[re.Pattern[str]], bool]:
    """(patterns, js-style?) for a file, by extension; ([], False) if none apply."""
    ext = posixpath.splitext(path)[1].lower()
    if ext == ".md":
        return MD, False
    if ext in (".html", ".htm"):
        return HTML, False
    if ext in (".js", ".mjs"):
        return JS, True
    return [], False


def _split(target: str) -> tuple[str, str]:
    """('path', '?query#anchor')."""
    m = re.search(r"[?#]", target)
    return (target[: m.start()], target[m.start():]) if m else (target, "")


def _relative(target: str, new_dir: str, orig: str, js: bool) -> str:
    rel = posixpath.relpath(target, new_dir or ".")
    if (js or orig.startswith("./")) and not rel.startswith("../"):
        rel = "./" + rel
    return rel


def fix_target(target: str, ctx: tuple[str, str, bool], mapper: Callable[[str], str],
               exists: Callable[[str], bool]) -> str | None:
    """The rewritten target, or None to leave it. ctx = (old file, new file, js-style)."""
    old_file, new_file, js = ctx
    if SCHEME.match(target) or "${" in target:
        return None
    part, suffix = _split(target)
    if not part:
        return None
    resolved = posixpath.normpath(posixpath.join(posixpath.dirname(old_file), part))
    if resolved.startswith("..") or not exists(resolved):
        return None
    moved = mapper(resolved)
    new_dir = posixpath.dirname(new_file)
    if moved == resolved and new_dir == posixpath.dirname(old_file):
        return None
    rel = _relative(moved, new_dir, part, js)
    if part.endswith("/") and not rel.endswith("/"):
        rel += "/"
    return None if rel + suffix == target else rel + suffix


def fix_text(text: str, old_file: str, new_file: str, mapper: Callable[[str], str],
             exists: Callable[[str], bool]) -> tuple[str, int]:
    """Rewrite every relative reference in one file; returns (text, references changed)."""
    pats, js = patterns_for(new_file)
    count = 0
    for pat in pats:
        def repl(m: re.Match[str]) -> str:
            nonlocal count
            new = fix_target(m.group(1), (old_file, new_file, js), mapper, exists)
            if new is None:
                return m.group(0)
            count += 1
            s, e = m.start(1) - m.start(0), m.end(1) - m.start(0)
            return m.group(0)[:s] + new + m.group(0)[e:]
        text = pat.sub(repl, text)
    return text, count
