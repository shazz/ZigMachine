#!/usr/bin/env python3
"""Phase 3: the website and every built cart out of docs/, into site/.

    python3 -I tools/reorg/phase3_site.py --dry-run
    python3 -I tools/reorg/phase3_site.py [--also]

Moves the pages, scripts, chips, carts, disks and assets (phase3_site.tsv), rewrites
every reference, then applies phase3_site.patch: the in-page URLs (a page fetches
"carts/demo-" + tag + ".zmd" now), the producers (build.zig's install dirs, mkdisks.sh,
cache_bust.py, the doc generators, channels.py, the C/Rust/port builds, the SDK, the
pre-push hook's "site/ up to date" check) and the harnesses' machine dir.

Before this lands on main, GitHub Pages must serve site/ (the Actions workflow
.github/workflows/pages.yml; see its header): classic Pages from main:/docs would serve
an empty site the moment this commit is pushed.
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # -I drops the script dir from sys.path

from phase import Phase, main  # noqa: E402

PHASE = Phase(
    name="phase3_site",
    message="reorg 3/4: the website and the carts into site/ (tools/reorg/phase3_site.py)",
    regen=[["python3", "tools/gen_tutorial.py"], ["python3", "tools/gen_docs.py"],
           ["python3", "tools/cache_bust.py"]],
)

if __name__ == "__main__":
    sys.exit(main(PHASE, sys.argv[1:]))
