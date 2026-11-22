#!/usr/bin/env python3
"""The shared rewrite engine of the repo reorganisation, and its --verify mode.

Library: `rewrite_all` computes every file's new text for one phase (relative
references first, then repo-rooted paths, then the hand patches), in memory.

CLI (after phases have run):

    python3 -I tools/reorg/rewrite.py --verify tools/reorg/phase1_docs.tsv [...]

greps every tracked text file for any OLD path of the given tables (and their
`forbid` patterns) and fails if one is left. Allowed to keep old paths: the stubs
left at old .md paths, and tools/reorg/ itself (its tables list every old path).
"""
from __future__ import annotations

import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # -I drops the script dir from sys.path

import mapping  # noqa: E402
import patches  # noqa: E402
import relfix  # noqa: E402
from reorg_lib import ROOT, changed_lines, is_rewritable, read_text, tracked  # noqa: E402


@dataclass
class Result:
    """What a phase would write: new path -> (text, lines changed), and failures."""

    texts: dict[str, tuple[str, int]] = field(default_factory=dict)
    relrefs: int = 0
    patch_fail: list[str] = field(default_factory=list)
    patch_hits: int = 0


def rewrite_paths(text: str, path: str, t: mapping.Table) -> str:
    """Replace every repo-rooted old path in `text` (file `path`, its new location)."""
    got = mapping.rewrite_regex(t, path)
    if got is None:
        return text
    rx, table = got
    keep = [s for p, s in t.allows if p == path]
    if keep:  # an `allow`ed line keeps its old path (a git show of an old revision)
        return "\n".join(ln if any(s in ln for s in keep) else rx.sub(lambda m: table[m.group(0)], ln)
                         for ln in text.split("\n"))
    return rx.sub(lambda m: table[m.group(0)], text)


def _exists_fn(files: list[str]):  # noqa: ANN202 (a closure over the tracked set)
    names = set(files)
    dirs = {p.rsplit("/", i)[0] for p in files for i in range(1, p.count("/") + 1)}
    return lambda p: p in names or p in dirs


def rewrite_all(t: mapping.Table, files: list[str], extra: list[str], plist: list[patches.Patch]) -> Result:
    """Every rewritable file's new text after the phase (only files that change are kept)."""
    res = Result()
    exists = _exists_fn(files)
    mapper = lambda p: mapping.map_path(t, p)  # noqa: E731
    for old in [f for f in files if is_rewritable(f)] + extra:
        new = t.moves.get(old, old)
        text = read_text(ROOT / old)
        if text is None:
            continue
        out, n = relfix.fix_text(text, old, new, mapper, exists)
        res.relrefs += n
        out = rewrite_paths(out, old, t)  # a scoped rule (scope=fpga/) follows the OLD home
        if out != text:
            res.texts[new] = (out, changed_lines(text, out))
    _apply_patches(res, plist, t)
    return res


def _apply_patches(res: Result, plist: list[patches.Patch], t: mapping.Table) -> None:
    for p in plist:
        if p.path in res.texts:
            text = res.texts[p.path][0]
        else:
            src = next((o for o, n in t.moves.items() if n == p.path), p.path)
            text = read_text(ROOT / src) or ""
        new, n = patches.apply(text, p)
        if not n:
            res.patch_fail.append(f"{p.path} (patch at line {p.line}): {p.old.splitlines()[0][:90]!r}")
            continue
        res.patch_hits += n
        base = res.texts.get(p.path, (text, 0))[1]
        res.texts[p.path] = (new, base + changed_lines(text, new))


def verify(tables: list[mapping.Table], allow: set[str]) -> list[str]:
    """Every place an old path (or a `forbid` pattern) is still mentioned."""
    hits: list[str] = []
    for f in tracked():
        if f in allow or not is_rewritable(f):
            continue
        text = read_text(ROOT / f)
        if text is None:
            continue
        for t in tables:
            hits += _hits_in(f, text, t)
    return hits


def _hits_in(f: str, text: str, t: mapping.Table) -> list[str]:
    out = []
    got = mapping.rewrite_regex(t, f)
    pats = ([got[0]] if got else []) + [mapping.glob_regex(g) for g, _ in t.globs]
    pats += [re.compile(r) for r, scope in t.forbids if not f.endswith(".md") and f.startswith(scope)]
    lines = text.split("\n")
    for rx in pats:
        for m in rx.finditer(text):
            n = text.count("\n", 0, m.start())
            if not any(f == p and s in lines[n] for p, s in t.allows):
                out.append(f"{f}:{n + 1}: [{m.group(0)}] {lines[n].strip()[:150]}")
    return out


def main(argv: list[str]) -> int:
    if not argv or argv[0] != "--verify" or len(argv) < 2:
        print(__doc__)
        return 2
    files = tracked()
    tables = [mapping.load(Path(p), files) for p in argv[1:]]
    allow = {s for t in tables for s in t.stubs}
    hits = verify(tables, allow)
    for h in hits:
        print(f"  old path left: {h}")
    print(f"verify: {'FAIL, ' + str(len(hits)) + ' old reference(s) left' if hits else 'clean'}")
    return 1 if hits else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
