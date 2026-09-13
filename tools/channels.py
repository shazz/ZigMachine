#!/usr/bin/env python3
"""Write docs/channels.json: the demos the monitor's +/- buttons step through.

Source of truth is apps/zig/scenes/catalog.zig (the menu's list), NOT a glob of
docs/demo-*.wasm: polyglot carts have no .zmd and must never become a channel.
Every channel must have a real docs/demo-<tag>.zmd; a missing one fails loudly.

Usage: tools/channels.py [--check]   (--check: validate only, write nothing)
"""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "apps/zig/scenes/catalog.zig"
OUT = ROOT / "docs/channels.json"

# ---- THE ORDER CHOICE -------------------------------------------------------
# "menu": the menu's order — menu.zig sorts catalog entries by NAME at comptime
#         (stable insertion sort, bytewise std.mem.lessThan), so +/- agree with
#         what the menu shows.
# "build": catalog append order (≈ cart index order, the legacy gh-page feel).
ORDER = "menu"

# Catalog entries that are not demo screens to channel-surf through:
EXCLUDE = {
    "gem": "the GEM desktop OS, not a screen",
    "st_replay": "a data disk that boots GEM + an app",
    # Hidden from the public page for now (Matt, 2026-09-12); still in the menu.
    "replicants": "REPS OLD, the pre-CODEF Replicants kept only for side-by-side comparison",
    "badflicker": "deliberately broken overscan test",
    "stream": "audio block-streaming test",
}

ENTRY = re.compile(r'\.\{\s*\.name\s*=\s*"([^"]*)"\s*,\s*\.tag\s*=\s*"([^"]*)"\s*\}')


def entries():
    text = CATALOG.read_text()
    start = text.find("ENTRIES")
    found = ENTRY.findall(text[start:])
    if not found:
        sys.exit(f"channels: no entries parsed from {CATALOG}")
    return found


def main():
    items = entries()
    if ORDER == "menu":
        # Python's sort is stable and compares str by code point, which matches
        # a bytewise compare for these ASCII names.
        items = sorted(items, key=lambda e: e[0].encode())
    elif ORDER != "build":
        sys.exit(f"channels: unknown ORDER {ORDER!r}")
    tags = [tag for _, tag in items if tag not in EXCLUDE]
    missing = [t for t in tags if not (ROOT / f"docs/demo-{t}.zmd").is_file()]
    if missing:
        sys.exit("channels: no disk for " + ", ".join(f"docs/demo-{t}.zmd" for t in missing))
    if "--check" not in sys.argv:
        OUT.write_text(json.dumps(tags, indent=1) + "\n")
    print(f"channels: {len(tags)} ({ORDER} order), excluded {len(items) - len(tags)}")


if __name__ == "__main__":
    main()
