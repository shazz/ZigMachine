#!/usr/bin/env python3
"""Phase 2: apps/*.mjs (with their fixtures and the perf/ library) into apps/harness/.

    python3 -I tools/reorg/phase2_harness.py --dry-run
    python3 -I tools/reorg/phase2_harness.py [--also]

Moves the harnesses, rewrites every caller (build.sh's gate lines, tools/, the other
harnesses, docs) and the harnesses' own file-relative references (../docs/..., ../zig/...),
and teaches tools/gate_scope.py (and its test) where harnesses live now.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # -I drops the script dir from sys.path

from phase import Phase, main  # noqa: E402

PHASE = Phase(
    name="phase2_harness",
    message="reorg 2/4: harnesses into apps/harness/ (tools/reorg/phase2_harness.py)",
    regen=[["python3", "-m", "unittest", "discover", "-s", "tools/tests", "-t", "tools", "-p", "test_gate_scope.py"]],
)

if __name__ == "__main__":
    sys.exit(main(PHASE, sys.argv[1:]))
