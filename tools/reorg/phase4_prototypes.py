#!/usr/bin/env python3
"""Phase 4: the port write-ups (prototypes/*/ANALYSIS.md) into docs/, then prototypes/ untracked.

    python3 -I tools/reorg/phase4_prototypes.py --dry-run
    python3 -I tools/reorg/phase4_prototypes.py [--also]

prototypes/ stays on disk (git rm -r --cached) and is already in .gitignore. Before that,
every tracked file OUTSIDE prototypes/ that names a tracked prototypes/ file (other than the
ANALYSIS.md that move) is listed: those are generators and references that will exist on
the owner's disk only. Code (not prose) among them STOPS the phase unless --accept-refs:
the gate must not read a file the repository no longer has.
"""
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # -I drops the script dir from sys.path

from phase import Phase, main  # noqa: E402
from reorg_lib import ROOT, is_rewritable, read_text, tracked  # noqa: E402

PHASE = Phase(
    name="phase4_prototypes",
    message="reorg 4/4: port write-ups into docs/ports, prototypes/ untracked (tools/reorg/phase4_prototypes.py)",
    untrack=["prototypes"],
)
CODE = re.compile(r"\.(?:zig|mjs|js|py|sh|c|h|zon|mk|json)$|(?:^|/)(?:Makefile|build\.sh)$")


def references() -> list[tuple[str, int, str, str]]:
    """(file, line, prototypes path, line text) for each mention of a tracked prototypes file."""
    files = tracked()
    proto = sorted((f for f in files if f.startswith("prototypes/") and not f.endswith("/ANALYSIS.md")),
                   key=len, reverse=True)
    rx = re.compile("|".join(re.escape(p) for p in proto)) if proto else None
    out = []
    for f in files:
        if rx is None or f.startswith(("prototypes/", "tools/reorg/")) or not is_rewritable(f):
            continue
        for n, line in enumerate((read_text(ROOT / f) or "").split("\n"), 1):
            out += [(f, n, m.group(0), line.strip()[:120]) for m in rx.finditer(line)]
    return out


def check(argv: list[str]) -> None:
    refs = references()
    code = [r for r in refs if CODE.search(r[0])]
    print(f"phase4: {len(refs)} mention(s) of tracked prototypes/ files outside it, {len(code)} in code:")
    for f, n, p, text in refs:
        print(f"  {'CODE ' if (f, n, p, text) in code else 'prose'} {f}:{n}: {p}   | {text}")
    if code and "--accept-refs" not in argv:
        sys.exit("phase4: STOP. Review the CODE lines above: if none is READ by the build or the gate "
                 "(comments naming a generator are fine), rerun with --accept-refs; otherwise move that "
                 "file out of prototypes/ first.")


if __name__ == "__main__":
    check(sys.argv[1:])
    sys.exit(main(PHASE, [a for a in sys.argv[1:] if a != "--accept-refs"]))
