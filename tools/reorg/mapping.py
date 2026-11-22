"""Read a reviewed mapping table (tools/reorg/*.tsv) into moves and rewrite rules.

One rule per line, tab-separated, `#` starts a comment:

    mv      OLD  NEW  [stub]       one tracked file; `stub` leaves "Moved to NEW" at OLD
    dir     OLD  NEW               every tracked file under OLD/ (and the bare dir name)
    glob    PAT  NEWDIR            every tracked file matching PAT in ONE directory -> NEWDIR/<name>
    rw      OLD  NEW  [scope=P]    rewrite only (a prefix such as docs/demo-), optionally only in files under P
    keep    PAT                    classified: stays where it is (for `check`)
    check   PAT                    every tracked file matching PAT must be classified, or the phase stops
    forbid  REGEX [scope=P]        --verify: REGEX must not appear in code (non-.md) files any more
    allow   FILE TEXT              --verify: an old path on a line of FILE containing TEXT is meant
                                   (a `git show <old rev>:docs/...` must keep the path of that rev)

Exact paths beat prefixes: rules are matched longest first.
"""
from __future__ import annotations

import fnmatch
import posixpath
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

# Text before a path that still makes it a repo-rooted mention: start, a non-path
# character, a ../ chain, a ${ROOT}/ or $(ROOT)/ or "…"/ join, an absolute checkout
# path, a GitHub blob/tree URL, or a \t / \n escape in a string ("M\tdocs/x.md").
LEAD = (r"(?:(?<![\w./-])|(?<=\.\./)|(?<=[^\w.]\./)|(?<=[)}\"'`]/)|(?<=ROOT/)|(?<=ZigMachine/)|(?<=zigmachine/)"
        r"|(?<=/main/)|(?<=\$PWD/)|(?<=\\[nt]))")


@dataclass
class Table:
    """A parsed mapping table."""

    moves: dict[str, str] = field(default_factory=dict)  # old file -> new file
    stubs: set[str] = field(default_factory=set)  # old paths that get a stub
    rules: list[tuple[str, str, str, str]] = field(default_factory=list)  # (kind, old, new, scope)
    keeps: list[str] = field(default_factory=list)
    checks: list[str] = field(default_factory=list)
    forbids: list[tuple[str, str]] = field(default_factory=list)  # (regex, scope)
    globs: list[tuple[str, str]] = field(default_factory=list)  # (pattern, new dir): --verify, local files
    allows: list[tuple[str, str]] = field(default_factory=list)  # (file, text on the line): --verify skips it
    dirs: list[tuple[str, str]] = field(default_factory=list)  # dir rules, longest first
    _regex: dict[tuple[str, ...], tuple[re.Pattern[str], dict[str, str]]] = field(default_factory=dict)


def _opts(cols: list[str]) -> dict[str, str]:
    return dict(c.split("=", 1) if "=" in c else (c, "1") for c in cols)


def _glob(pat: str, files: list[str]) -> list[str]:
    """fnmatch where `*` stays inside one directory."""
    d, b = posixpath.split(pat)
    return [f for f in files if f.count("/") == pat.count("/")
            and fnmatch.fnmatchcase(posixpath.dirname(f), d) and fnmatch.fnmatchcase(posixpath.basename(f), b)]


def _mv(t: Table, a: str, b: str, opts: dict[str, str]) -> None:
    t.moves[a] = b
    t.rules.append(("exact", a, b, ""))
    if "stub" in opts:
        t.stubs.add(a)


def _dir(t: Table, a: str, b: str, files: list[str]) -> None:
    for f in (f for f in files if f.startswith(a + "/")):
        t.moves[f] = b + f[len(a):]
    t.rules.append(("dir", a, b, ""))


def _glob_mv(t: Table, a: str, b: str, files: list[str]) -> None:
    """A glob never re-routes a file an earlier, more specific line already moved."""
    t.globs.append((a, b))
    for f in _glob(a, files):
        if f not in t.moves:
            t.moves[f] = posixpath.join(b, posixpath.basename(f))
            t.rules.append(("exact", f, t.moves[f], ""))


def _add_line(t: Table, cols: list[str], files: list[str]) -> None:
    kind, a = cols[0], cols[1]
    b = cols[2] if len(cols) > 2 else ""
    opts = _opts(cols[3:] if kind in ("mv", "rw") else cols[2:] if kind == "forbid" else [])
    if kind == "mv":
        _mv(t, a, b, opts)
    elif kind == "dir":
        _dir(t, a, b, files)
    elif kind == "glob":
        _glob_mv(t, a, b, files)
    elif kind == "rw":
        t.rules.append(("prefix", a, b, opts.get("scope", "")))
    elif kind in ("keep", "check"):
        (t.keeps if kind == "keep" else t.checks).append(a)
    elif kind == "forbid":
        t.forbids.append((a, opts.get("scope", "")))
    elif kind == "allow":
        t.allows.append((a, b))
    else:
        sys.exit(f"reorg: unknown mapping kind {kind!r}")


def load(path: Path, files: list[str]) -> Table:
    """Parse the table against the tracked file list."""
    t = Table()
    for n, raw in enumerate(path.read_text().splitlines(), 1):
        line = raw.split(" #", 1)[0].rstrip() if not raw.startswith("forbid") else raw.rstrip()
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        cols = [c for c in line.split("\t") if c]
        if len(cols) < 2:
            sys.exit(f"reorg: {path.name}:{n}: expected tab-separated columns: {raw!r}")
        _add_line(t, cols, files)
    t.dirs = sorted(((o, n) for k, o, n, _ in t.rules if k == "dir"), key=lambda r: -len(r[0]))
    return t


def unclassified(t: Table, files: list[str]) -> list[str]:
    """Tracked files a `check` pattern covers that no rule moves or keeps."""
    out = []
    for pat in t.checks:
        for f in _glob(pat, files):
            if f not in t.moves and not any(fnmatch.fnmatchcase(f, k) for k in t.keeps):
                out.append(f)
    return out


def map_path(t: Table, path: str) -> str:
    """Where a repo path lives after the phase (files and directories)."""
    if path in t.moves:
        return t.moves[path]
    for old, new in t.dirs:
        if path == old or path.startswith(old + "/"):
            return new + path[len(old):]
    return path


def _alt(kind: str, old: str) -> str:
    esc = re.escape(old)
    if kind == "exact":
        return esc + r"(?![\w-])"
    if kind == "dir":
        return esc + r"(?=/|[^\w.-]|$)"
    return esc


def rewrite_regex(t: Table, path: str) -> tuple[re.Pattern[str], dict[str, str]] | None:
    """The one regex (longest rule first) and old->new map that apply in file `path`."""
    rules = [r for r in t.rules if not r[3] or path.startswith(r[3])]
    if not rules:
        return None
    key = tuple(sorted({r[3] for r in rules}))
    if key in t._regex:
        return t._regex[key]
    rules.sort(key=lambda r: -len(r[1]))
    alts = "|".join(_alt(k, o) for k, o, _, _ in rules)
    t._regex[key] = (re.compile(LEAD + "(?:" + alts + ")"), {o: n for _, o, n, _ in rules})
    return t._regex[key]


def glob_regex(pat: str) -> re.Pattern[str]:
    """A glob as a repo-rooted mention (`*` stays inside one directory): for --verify."""
    body = "".join(r"[\w.-]*" if c == "*" else re.escape(c) for c in pat)
    return re.compile(LEAD + body + r"(?![\w-])")
