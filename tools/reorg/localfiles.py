"""Untracked files that live inside a moved directory go with it.

git mv moves only what git tracks. A checkout also holds git-ignored files in the
moved places, and some matter: docs/music/local.xm (the owner's own tune, music_debug
key 6), the HVSC .sid tunes, the SDK template's docs/demo-hello.* and docs/.sdk/
marker. Left behind they would vanish from the build. They are moved with a plain
rename (never committed), and the emptied directories are removed.
"""
from __future__ import annotations

import fnmatch
import os
from pathlib import Path

import mapping
from reorg_lib import ROOT


def _under(old: str) -> list[str]:
    base = ROOT / old
    if not base.is_dir():
        return []
    return sorted(str(p.relative_to(ROOT)) for p in base.rglob("*") if p.is_file() or p.is_symlink())


def plan(t: mapping.Table, tracked: set[str]) -> list[tuple[str, str]]:
    """(old, new) for every untracked file on disk a dir or glob rule covers."""
    out: list[tuple[str, str]] = []
    for old, new in t.dirs:
        out += [(f, new + f[len(old):]) for f in _under(old) if f not in tracked]
    for pat, dest in t.globs:
        d = ROOT / os.path.dirname(pat)
        if d.is_dir():
            for p in sorted(d.iterdir()):
                rel = str(p.relative_to(ROOT))
                if p.is_file() and rel not in tracked and fnmatch.fnmatchcase(rel, pat):
                    out.append((rel, f"{dest}/{p.name}"))
    return out


def move(pairs: list[tuple[str, str]], dirs: list[tuple[str, str]]) -> list[str]:
    """Rename each file (never over an existing one); prune emptied dirs. Returns the conflicts."""
    clash = []
    for old, new in pairs:
        dst = ROOT / new
        if dst.exists():
            clash.append(f"{old} -> {new}: the target exists, left in place")
            continue
        dst.parent.mkdir(parents=True, exist_ok=True)
        (ROOT / old).rename(dst)
    for old, _ in dirs:
        _prune(ROOT / old)
    return clash


def _prune(d: Path) -> None:
    if not d.is_dir():
        return
    for sub in sorted((p for p in d.rglob("*") if p.is_dir()), key=lambda p: -len(p.parts)):
        if not any(sub.iterdir()):
            sub.rmdir()
    if not any(d.iterdir()):
        d.rmdir()
