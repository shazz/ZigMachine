#!/usr/bin/env python3
"""ZigMachine programmer's-guide generator.

Parses the sealed HW ABI headers (machine/sdk/*.zig) and the open ZigOS library
(libs/zig/*.zig) for their public surface + doc comments, and emits a single
self-contained reference (docs/ZIGMACHINE_GUIDE.html) with a register map, an
ABI/library reference, hand-written examples, and the disk/cart-format prose
rendered from docs/FLOPPY_DISK.md and the music guide from docs/MUSIC.md.

The reference is generated from source so signatures never drift; the prose and
examples live in tools/docgen/guide_content.py. The teaching half is a separate
page — see tools/gen_tutorial.py.

  python3 tools/gen_docs.py            # write the guide
  python3 tools/gen_docs.py --check    # fail if the committed guide is stale
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from docgen import ROOT  # noqa: E402
from docgen.guide_render import build, undated  # noqa: E402


def main() -> None:
    out = ROOT / "docs" / "ZIGMACHINE_GUIDE.html"
    fresh = build()
    if "--check" in sys.argv:
        # A doc edit (MUSIC.md, FLOPPY_DISK.md, a doc comment) that was never
        # regenerated leaves the published guide stale (#88's upload section did).
        if not out.is_file() or undated(out.read_text()) != undated(fresh):
            sys.exit(f"{out.relative_to(ROOT)} is stale: run python3 tools/gen_docs.py and commit it")
        print(f"{out.relative_to(ROOT)} matches its sources")
        return
    out.write_text(fresh)
    print(f"wrote {out.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
