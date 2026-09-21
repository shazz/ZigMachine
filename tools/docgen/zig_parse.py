"""Lightweight, line-oriented parsers for the Zig sources the docs describe.

Not a full Zig parser: it reads `pub const` / `pub extern fn` / `pub fn` lines
and their `//` doc comments, so generated signatures never drift from source.
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field
from pathlib import Path


@dataclass
class Item:
    name: str
    sig: str
    doc: str = ""


@dataclass
class Group:
    title: str
    blurb: str
    items: list[Item] = field(default_factory=list)


def _leading_doc(lines: list[str], idx: int) -> str:
    """Contiguous `//` comment lines immediately above line `idx`."""
    out: list[str] = []
    j = idx - 1
    while j >= 0:
        s = lines[j].strip()
        if s.startswith("//"):
            out.append(s.lstrip("/").strip())
            j -= 1
        else:
            break
    return " ".join(reversed(out))


def _trailing_doc(line: str) -> str:
    m = re.search(r"//\s*(.*)$", line)
    return m.group(1).strip() if m else ""


def parse_consts(path: Path, name_re: str) -> list[Item]:
    """`pub const <name> : type = value; // doc` lines whose name matches name_re."""
    items: list[Item] = []
    for line in path.read_text().splitlines():
        m = re.match(rf"\s*pub const ({name_re})\s*:[^=]+=\s*([^;]+);", line)
        if m:
            items.append(Item(m.group(1), m.group(2).strip(), _trailing_doc(line)))
    return items


def parse_externs(path: Path) -> list[Item]:
    """`pub extern fn name(args) ret; // doc` — the HW ABI exports."""
    items: list[Item] = []
    for line in path.read_text().splitlines():
        m = re.match(r"\s*pub extern fn\s+(\w+)\s*(\([^)]*\)[^;]*);", line)
        if m:
            items.append(Item(m.group(1), f"{m.group(1)}{m.group(2).strip()}", _trailing_doc(line)))
    return items


def parse_struct_methods(path: Path, struct: str) -> list[Item]:
    """`pub fn name(...) ret {` methods inside a top-level `pub const <struct> = struct`.

    Only a column-0 struct opens a scope and only its `};` closes it, so a nested
    helper struct (Blitter.FillOpts) no longer swallows every method after it —
    the published guide listed 1 of Blitter's 13 methods for that reason.
    """
    lines = path.read_text().splitlines()
    items: list[Item] = []
    inside = False
    for i, line in enumerate(lines):
        if not inside:
            inside = re.match(rf"pub const {struct}\s*=\s*(?:extern\s+)?struct\b", line) is not None
            continue
        if line.startswith("};"):
            break
        fm = re.match(r"    pub fn\s+(\w+)\s*(\(.*)$", line)
        if fm:
            sig = re.sub(r"\s*\{?\s*$", "", fm.group(2).rstrip())  # drop trailing brace
            items.append(Item(fm.group(1), f"{fm.group(1)}{sig}", _leading_doc(lines, i)))
    return items
