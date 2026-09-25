#!/usr/bin/env python3
"""Write docs/channels.json + docs/cart-names.json from the menu's catalog.

Each channel is a RECORD: {"tag", "title", "type"} — the tag the host boots,
the human name, and the machine the screen comes from. The title and type are
what the monitor's VHS name card prints when a cart boots (docs/cart-osd.js).

The type is the TRAILING COMMENT on the catalog line (`}, // atari st`), not a
field on Entry: it is host presentation metadata the menu cart would otherwise
carry as dead bytes, and a comment on the line you already edit when adding a
screen cannot drift the way a second list would. An entry whose comment names no
known type FAILS here — a screen silently labelled with the wrong machine is
worse than a build error.

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
    # The full Union cracktro (union_intro) already flows into this main screen
    # (Matt, 2026-09-13); still in the menu.
    "union_main": "the Union main screen alone; union_intro already plays it",
    # Still in the menu, so a newcomer can boot the screen docs/TUTORIAL.md builds.
    "tutorial": "the docs/TUTORIAL.md teaching screen, not a demo",
}

# The Union Demo's screens are reached only through the union_demo hub's doors
# (Matt, 2026-09-13), never by +/-. Every union_* tag is one, except these two.
# The Union Demo's channel is its intro splash, as the demo opens on it; the
# street (union_demo) is reached from there with Space.
UNION_PREFIX = "union_"
UNION_CHANNELS = {"union_intro_screen", "union_intro"}  # the demo's opening, and the cracktro leading to it


def excluded(tag):
    return tag in EXCLUDE or (tag.startswith(UNION_PREFIX) and tag not in UNION_CHANNELS)

# The machines a screen can come from. "unknown" is a deliberate label, not a
# default: it means the scene's own source does not say and nobody has checked.
KINDS = ("atari st", "atari falcon", "amiga", "zigmachine", "system", "unknown")

# name, tag, and the trailing comment the type is read from. The comment may go
# on with prose after the type ("// atari st — the demo opens on ...").
ENTRY = re.compile(
    r'\.\{\s*\.name\s*=\s*"([^"]*)"\s*,\s*\.tag\s*=\s*"([^"]*)"\s*\}\s*,?[ \t]*(?://[ \t]*([^\n]*))?')


def kind_of(comment):
    """The type a catalog line's trailing comment names, or None."""
    c = (comment or "").strip().lower()
    for k in sorted(KINDS, key=len, reverse=True):
        if c == k or c.startswith(k + " "):
            return k
    return None


def entries():
    """[(name, tag, type)] for every catalog entry, or exit loudly."""
    text = CATALOG.read_text()
    start = text.find("ENTRIES")
    found = ENTRY.findall(text[start:])
    if not found:
        sys.exit(f"channels: no entries parsed from {CATALOG}")
    typed = [(name, tag, kind_of(comment)) for name, tag, comment in found]
    untyped = [tag for _, tag, kind in typed if kind is None]
    if untyped:
        sys.exit(f"channels: no type on {', '.join(untyped)} in {CATALOG}. "
                 f"End the entry's line with a comment naming one of: {', '.join(KINDS)}.")
    return typed


def main():
    items = entries()
    if ORDER == "menu":
        # Python's sort is stable and compares str by code point, which matches
        # a bytewise compare for these ASCII names.
        items = sorted(items, key=lambda e: e[0].encode())
    elif ORDER != "build":
        sys.exit(f"channels: unknown ORDER {ORDER!r}")
    channels = [{"tag": tag, "title": name, "type": kind}
                for name, tag, kind in items if not excluded(tag)]
    tags = [c["tag"] for c in channels]
    missing = [t for t in tags if not (ROOT / f"docs/demo-{t}.zmd").is_file()]
    if missing:
        sys.exit("channels: no disk for " + ", ".join(f"docs/demo-{t}.zmd" for t in missing))
    if "--check" not in sys.argv:
        OUT.write_text(json.dumps(channels, indent=1) + "\n")
    kinds = ", ".join(f"{k}={sum(1 for c in channels if c['type'] == k)}" for k in KINDS)
    print(f"channels: {len(channels)} ({ORDER} order), excluded {len(items) - len(channels)} [{kinds}]")


if __name__ == "__main__":
    main()
