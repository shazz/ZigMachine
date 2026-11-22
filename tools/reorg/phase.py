"""The flow every phase shares: check, plan, move, rewrite, patch, regenerate, verify, commit.

A phase is one table (`<name>.tsv`), an optional `<name>.patch`, regeneration commands
and a commit message. It is idempotent: once its moves are committed it says so and
exits 0; a half-done tree is refused (git restore + git clean, then run it again).
"""
from __future__ import annotations

import argparse
import os
import sys
from dataclasses import dataclass, field
from pathlib import Path

import localfiles
import mapping
import patches
import rewrite
from reorg_lib import ROOT, also_files, git, require_clean, run, tracked

HERE = Path(__file__).resolve().parent
# Untracked local instructions (.claude is git-ignored): rewritten with --also, never committed.
DEFAULT_ALSO = [".claude/skills/**/*.md", ".claude/agents/*.md", ".claude/commands/*.md",
                ".claude/hooks/*", "tools/private_tools/**/*.py", "tools/private_tools/**/*.md"]


@dataclass
class Phase:
    """One phase's inputs."""

    name: str  # tools/reorg/<name>.tsv and <name>.patch
    message: str  # the commit subject
    regen: list[list[str]] = field(default_factory=list)  # commands run after the rewrite
    untrack: list[str] = field(default_factory=list)  # `git rm -r --cached` these (phase 4)


def parse_args(argv: list[str]) -> argparse.Namespace:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true", help="print every move and rewrite; change nothing")
    ap.add_argument("--also", action="store_true",
                    help="also rewrite the untracked local instructions (" + ", ".join(DEFAULT_ALSO) + ")")
    ap.add_argument("--no-commit", action="store_true", help="leave the result uncommitted (to inspect it)")
    ap.add_argument("--no-regen", action="store_true", help="skip the regeneration commands (debugging)")
    return ap.parse_args(argv)


def state(t: mapping.Table, files: list[str]) -> str:
    """'todo', 'done' or 'partial', from where the moved files are."""
    have = set(files)
    src = sum(1 for o in t.moves if o in have)
    dst = sum(1 for n in t.moves.values() if n in have)
    if not t.moves and not files:
        return "todo"
    if src == len(t.moves) and dst == 0:
        return "todo"
    return "done" if src == 0 or (src == len(t.stubs) and dst == len(t.moves)) else "partial"


def report(t: mapping.Table, res: rewrite.Result, local: list[tuple[str, str]]) -> None:
    for old, new in sorted(t.moves.items()):
        print(f"git mv {old} {new}{'   (+ stub)' if old in t.stubs else ''}")
    for old, new in local:
        print(f"mv (untracked, local only) {old} {new}")
    for path, (_, n) in sorted(res.texts.items()):
        print(f"rewrite {path}: {n} line(s)")
    print(f"SUMMARY: {len(t.moves)} file(s) moved (+ {len(local)} untracked), {len(t.stubs)} stub(s), "
          f"{len(res.texts)} file(s) rewritten ({sum(n for _, n in res.texts.values())} lines), {res.relrefs} relative reference(s) re-pointed, "
          f"{res.patch_hits} patch replacement(s)")


def apply(t: mapping.Table, res: rewrite.Result) -> None:
    """git mv everything, then write the rewritten texts at their new paths."""
    for old, new in sorted(t.moves.items()):
        (ROOT / new).parent.mkdir(parents=True, exist_ok=True)
        git("mv", old, new)
    for path, (text, _) in res.texts.items():
        (ROOT / path).write_text(text, encoding="utf-8")


def write_stubs(t: mapping.Table) -> list[str]:
    """One line at each old .md path, so outside links still land somewhere."""
    for old in sorted(t.stubs):
        new = t.moves[old]
        rel = os.path.relpath(new, os.path.dirname(old) or ".")
        (ROOT / old).write_text(f"Moved to [{new}]({rel}).\n", encoding="utf-8")
    return sorted(t.stubs)


def commit(msg: str, paths: list[str], skip: tuple[str, ...] = ()) -> None:
    """Stage by name (the rewritten files, the regenerated ones) and commit.

    `skip`: prefixes just untracked (git rm --cached): never staged again, even when rewritten on disk.
    """
    changed = [ln[3:] for ln in git("status", "--porcelain", "--untracked-files=no").splitlines()]
    names = sorted(n for n in set(paths) | {c.split(" -> ")[-1] for c in changed} if not n.startswith(skip))
    for i in range(0, len(names), 200):
        git("add", "-f", "--", *names[i:i + 200])  # -f: tracked files under the ignored prototypes/
    git("commit", "-q", "-m", msg)
    print(f"committed: {msg}")


def _preflight(ph: Phase, t: mapping.Table, files: list[str]) -> bool:
    """False when the phase already ran; exits on an unclassified file or a half-done tree."""
    bad = mapping.unclassified(t, files)
    st = state(t, files)
    if st == "done":
        print(f"{ph.name}: already applied (its moves are in the tree); nothing to do")
        return False
    if bad:
        sys.exit(f"{ph.name}: STOP, files no rule classifies (add a mv/glob/keep line to {ph.name}.tsv):\n  "
                 + "\n  ".join(bad))
    if st == "partial":
        sys.exit(f"{ph.name}: STOP, the tree is half-moved; `git reset --hard` to the last commit and rerun")
    return True


def _finish(ph: Phase, t: mapping.Table, res: rewrite.Result, args: argparse.Namespace,
            extra: list[str], local: list[tuple[str, str]]) -> int:
    apply(t, res)
    for clash in localfiles.move(local, t.dirs):
        print(f"  WARNING untracked file not moved: {clash}")
    for path in ph.untrack:
        git("rm", "-r", "-q", "--cached", "--", path)
    for cmd in [] if args.no_regen else ph.regen:
        run(cmd, False)
    if extra:  # git-ignored local files: rewritten in place, never committed
        print(f"rewrote {sum(1 for p in res.texts if p in extra)} untracked local file(s) (--also); not committed")
    if not args.no_commit:
        commit(ph.message, [p for p in res.texts if p not in extra], tuple(u + "/" for u in ph.untrack))
        if t.stubs:
            commit(f"{ph.message} (stubs at the old paths)", write_stubs(t))
    elif t.stubs:
        write_stubs(t)
    hits = rewrite.verify([mapping.load(HERE / f"{ph.name}.tsv", tracked())], t.stubs)
    for h in hits:
        print(f"  old path left: {h}")
    print(f"{ph.name}: verify {'FAIL (' + str(len(hits)) + ' left)' if hits else 'clean'}")
    return 1 if hits else 0


def main(ph: Phase, argv: list[str]) -> int:
    args = parse_args(argv)
    sys.stdout.reconfigure(line_buffering=True)  # keep our lines in order with the regen tools' output
    require_clean()
    files = tracked()
    t = mapping.load(HERE / f"{ph.name}.tsv", files)
    if not _preflight(ph, t, files):
        return 0
    extra = also_files(DEFAULT_ALSO) if args.also else []
    res = rewrite.rewrite_all(t, files, extra, patches.load(HERE / f"{ph.name}.patch"))
    local = localfiles.plan(t, set(files))
    report(t, res, local)
    if res.patch_fail:
        print(f"{ph.name}: STOP, {len(res.patch_fail)} patch(es) no longer match:\n  " + "\n  ".join(res.patch_fail))
        return 1
    if args.dry_run:
        for cmd in ph.regen:
            run(cmd, True)
        print(f"{ph.name}: dry run, nothing changed")
        return 0
    return _finish(ph, t, res, args, extra, local)
