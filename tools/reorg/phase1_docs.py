#!/usr/bin/env python3
"""Phase 1: human docs into docs/guide, hardware, hardware/studies, os, project.

    python3 -I tools/reorg/phase1_docs.py --dry-run     # every git mv + rewritten file, nothing changed
    python3 -I tools/reorg/phase1_docs.py [--also]      # do it, as one commit (+ one for the stubs)

Moves every docs/*.md (classified in phase1_docs.tsv), the root BUGS.md / PORTS.md /
decisions.md (-> docs/project/DECISIONS.md) and fpga/review/*.md + reports/ +
fpga/bench_results/ (-> docs/hardware/studies/), rewrites every reference repo-wide,
regenerates the two pages rendered from the .md, and leaves a one-line stub at each old
.md path. --also rewrites the untracked .claude/ skills/agents/commands too.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # -I drops the script dir from sys.path

from phase import Phase, main  # noqa: E402

PHASE = Phase(
    name="phase1_docs",
    message="reorg 1/4: docs into docs/guide, hardware, os, project (tools/reorg/phase1_docs.py)",
    regen=[["python3", "tools/gen_tutorial.py"], ["python3", "tools/gen_docs.py"],
           ["python3", "tools/cache_bust.py"]],
)

if __name__ == "__main__":
    sys.exit(main(PHASE, sys.argv[1:]))
