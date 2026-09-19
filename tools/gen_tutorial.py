#!/usr/bin/env python3
"""ZigMachine tutorial-page generator.

Renders docs/TUTORIAL.md into docs/TUTORIAL.html: the teaching page, split out
of the reference guide so a newcomer and someone looking up a register no longer
land on the same 1900-line document.

The markdown stays the single source of truth and stays readable on GitHub — the
structure the generator relies on is documented in tools/docgen/tutorial_parse.py
and a malformed heading fails this script rather than vanishing from the page.

  python3 tools/gen_tutorial.py            # write the page
  python3 tools/gen_tutorial.py --check    # fail if the committed page is stale
"""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from docgen import ROOT  # noqa: E402
from docgen.tutorial_render import build, unstamped  # noqa: E402


def main() -> None:
    out = ROOT / "docs" / "TUTORIAL.html"
    fresh = build()
    if "--check" in sys.argv:
        # Same guard as the guide: an edit to TUTORIAL.md that was never
        # regenerated would leave the published page stale. Compared without
        # cache_bust.py's ?v= hashes, which it stamps in after generation.
        if not out.is_file() or unstamped(out.read_text()) != unstamped(fresh):
            sys.exit(f"{out.relative_to(ROOT)} is stale: run python3 tools/gen_tutorial.py and commit it")
        print(f"{out.relative_to(ROOT)} matches docs/TUTORIAL.md")
        return
    out.write_text(fresh)
    print(f"wrote {out.relative_to(ROOT)} ({len(fresh):,} bytes)")


if __name__ == "__main__":
    main()
