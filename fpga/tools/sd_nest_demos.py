"""Print the shell lines that move a card's flat CARTS/demos/ into its platform folders.

    uv run python tools/sd_nest_demos.py [--files LISTING] [--root /mnt/sd] > nest.sh

Before 7 Nov every demo sat at CARTS/demos/demo-<tag>.zmd; since then at
CARTS/demos/<platform>/demo-<tag>.zmd (tools/shelf_category.py). This prints, never runs:
the remount, one `mkdir -p` a platform, one `mv` a disk, then the remount back. With --files
(an `ls` of the card's CARTS/demos/, one name a line) only those disks move; without it, every
demo the repo knows. A name that is not a demo the repo can place stops it (exit 1, named on
stderr): a guessed move would hide the disk in the wrong folder. The new shelf.txt
(tools/shelf_meta.py) must replace the card's: glass finds an old line by its file name, but
the paths it lists should be the card's.
"""

from __future__ import annotations

import argparse
import re
import shlex
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import sd_layout
import shelf_category

DISK = re.compile(r"^demo-(.+)\.zmd$")


def moves(names: list[str]) -> tuple[list[tuple[str, str]], list[str]]:
    """(from, to) under CARTS/ for each disk name in demos/, and why any name cannot move."""
    out, bad = [], []
    for name in names:
        m = DISK.match(name)
        try:
            if not m or shelf_category.category(m.group(1)) != "demos":
                raise shelf_category.UnknownCategory(f"{name}: not a demo's disk")
            out.append((f"demos/{name}", shelf_category.disk_path(m.group(1))))
        except shelf_category.UnknownCategory as e:
            bad.append(str(e))
    return out, bad


def script(pairs: list[tuple[str, str]], root: str) -> list[str]:
    """The lines: remount rw, the folders, the moves, remount ro."""
    carts = f"{root}/{sd_layout.CARTS}"
    dirs = sorted({to.rsplit("/", 1)[0] for _, to in pairs})
    return [
        f"mount -o remount,rw {shlex.quote(root)}",
        *(f"mkdir -p {shlex.quote(f'{carts}/{d}')}" for d in dirs),
        *(f"mv {shlex.quote(f'{carts}/{a}')} {shlex.quote(f'{carts}/{b}')}" for a, b in pairs),
        "sync",
        f"mount -o remount,ro {shlex.quote(root)}",
    ]


def demo_names() -> list[str]:
    """Every demo disk the repo can put on a card."""
    return [f"demo-{t}.zmd" for t in shelf_category.every_tag() if shelf_category.category(t) == "demos"]


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--files", type=Path, help="the card's CARTS/demos/ listing, one name a line")
    p.add_argument("--root", default="/mnt/sd", help="where the card is mounted (S99glass: /mnt/sd)")
    a = p.parse_args()
    names = [n.strip() for n in a.files.read_text().splitlines() if n.strip()] if a.files else demo_names()
    pairs, bad = moves(names)
    if bad:
        print("\n".join(bad), file=sys.stderr)
        return 1
    print(f"# {len(pairs)} disks: CARTS/demos/ -> CARTS/demos/<platform>/ (tools/sd_nest_demos.py)")
    print("\n".join(script(pairs, a.root)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
