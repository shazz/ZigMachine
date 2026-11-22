"""Git and file helpers shared by the reorganisation phases (tools/reorg/run_all.sh).

Stdlib only, run with `python3 -I`. Nothing here decides WHAT moves: the mapping
tables (tools/reorg/*.tsv) do, and mapping.py reads them.
"""
from __future__ import annotations

import difflib
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent

# Never rewritten: vendored code, generated binaries, and this tool (its tables list every old path).
SKIP_PREFIXES = ("third_party/", "tools/reorg/")
SKIP_PARTS = ("upstream", "third_party")
BINARY_EXT = {".wasm", ".zmd", ".img", ".png", ".jpg", ".gif", ".bin", ".raw", ".gz", ".br", ".ttf",
              ".sndh", ".mod", ".xm", ".sid", ".ym", ".ymraw", ".hip", ".sap", ".kt", ".mp3", ".wav",
              ".pi1", ".neo", ".prg", ".st", ".msa", ".o", ".a", ".zip", ".pdf", ".dat", ".rpt"}


def git(*args: str, check: bool = True) -> str:
    """Run git in the repo root and return stdout."""
    res = subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True)
    if check and res.returncode != 0:
        sys.exit(f"reorg: git {' '.join(args)} failed:\n{res.stderr}")
    return res.stdout


def tracked() -> list[str]:
    """Every tracked path (repo-relative, posix)."""
    return [p for p in git("ls-files", "-z").split("\0") if p]


def require_clean() -> None:
    """Refuse to run on a dirty tree: a phase must be one reviewable commit."""
    dirty = git("status", "--porcelain", "--untracked-files=no")
    if dirty.strip():
        sys.exit("reorg: the working tree has uncommitted changes; commit or stash them first:\n" + dirty)


def is_rewritable(path: str) -> bool:
    """A tracked file the rewriter may edit: text, not vendored, not this tool."""
    if path.startswith(SKIP_PREFIXES) or any(p in SKIP_PARTS for p in path.split("/")[:-1]):
        return False
    return Path(path).suffix.lower() not in BINARY_EXT


def read_text(path: Path) -> str | None:
    """The file as UTF-8 text, or None for a binary / undecodable / missing file."""
    try:
        data = path.read_bytes()
    except (FileNotFoundError, IsADirectoryError):
        return None
    if b"\0" in data[:8192]:
        return None
    try:
        return data.decode("utf-8")
    except UnicodeDecodeError:
        return None


def also_files(globs: list[str]) -> list[str]:
    """Untracked local instruction files (CLAUDE.md, .claude/ skills...) asked for with --also."""
    out: list[str] = []
    for pattern in globs:
        out += sorted(str(p.relative_to(ROOT)) for p in ROOT.glob(pattern) if p.is_file())
    return out


def changed_lines(old: str, new: str) -> int:
    """How many lines the new version adds or changes (a diff's + lines)."""
    a, b = old.splitlines(), new.splitlines()
    if len(a) == len(b):  # the path rewriter never adds lines: a cheap pairwise count
        return sum(1 for x, y in zip(a, b, strict=True) if x != y)
    diff = difflib.unified_diff(a, b, lineterm="", n=0)
    return sum(1 for ln in diff if ln.startswith("+") and not ln.startswith("+++"))


def run(cmd: list[str], dry: bool) -> None:
    """Run a regeneration command from the repo root (printed, not run, in a dry run)."""
    print(f"  run: {' '.join(cmd)}")
    if dry:
        return
    res = subprocess.run(cmd, cwd=ROOT)
    if res.returncode != 0:
        sys.exit(f"reorg: {' '.join(cmd)} failed (exit {res.returncode})")
