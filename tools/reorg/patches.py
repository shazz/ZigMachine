"""Literal per-file patches: the references no path table can see.

`"docs"` passed as a machine directory, `ROOT / "docs" / f"demo-{tag}.zmd"`, a page
fetching `"demo-" + tag + ".zmd"` relative to the document... Each is listed by hand in
a phase's .patch file, reviewed, and applied to the file at its NEW path:

    === path/after/the/move
    <<<
    old text (one or more lines)
    ---
    new text
    >>>

Every `old` must occur at least once (all occurrences are replaced) or the phase stops:
a patch that no longer matches means the source changed since the table was written.
"""
from __future__ import annotations

import sys
from dataclasses import dataclass
from pathlib import Path


@dataclass
class Patch:
    """One literal replacement in one file."""

    path: str
    old: str
    new: str
    line: int  # where it is in the .patch file, for messages


def _block(lines: list[str], i: int, path: str, src: str) -> tuple[Patch, int]:
    """Parse one <<< old --- new >>> block starting after the <<< line at index i."""
    start = i
    old: list[str] = []
    new: list[str] = []
    cur = old
    while i < len(lines) and lines[i] != ">>>":
        if lines[i] == "---" and cur is old:
            cur = new
        else:
            cur.append(lines[i])
        i += 1
    if i >= len(lines) or cur is old:
        sys.exit(f"reorg: {src}:{start}: unterminated patch block")
    return Patch(path, "\n".join(old), "\n".join(new), start), i + 1


def load(path: Path) -> list[Patch]:
    """Parse a .patch file; a missing file means no patches."""
    if not path.exists():
        return []
    lines = path.read_text().split("\n")
    out: list[Patch] = []
    target, i = "", 0
    while i < len(lines):
        line = lines[i]
        if line.startswith("=== "):
            target, i = line[4:].strip(), i + 1
        elif line == "<<<":
            if not target:
                sys.exit(f"reorg: {path.name}:{i + 1}: patch block before any === file line")
            patch, i = _block(lines, i + 1, target, path.name)
            out.append(patch)
        else:
            i += 1
    return out


def apply(text: str, patch: Patch) -> tuple[str, int]:
    """(patched text, occurrences replaced). 0 occurrences = the caller stops."""
    n = text.count(patch.old)
    return (text.replace(patch.old, patch.new), n) if n else (text, 0)
