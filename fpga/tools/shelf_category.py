"""The SD card's folders: which one each cart's fat disk goes in (docs/FPGA_GLASS.md, "The menu").

    uv run python tools/shelf_category.py [--check] [--path TAG]

The glass OSD lists the shelf's folders first and a folder's carts inside it, so every disk
the card carries sits at CARTS/<category>/demo-<tag>.zmd (tools/glass_shelf.py), and a demo one
level further down, by the machine it comes from: CARTS/demos/<platform>/demo-<tag>.zmd
(PLATFORMS: atari_st, amiga, atari_falcon, atari_xl, c64, kestrel). The category comes from
where the repo already says it:

- TABLE first: the carts a rule gets wrong or cannot know (a game ported from the ST, a test
  cart, a native cart outside the catalog);
- a Union Demo screen (union_*: reached only through the hub's doors) is a demo;
- else the catalog's machine type (apps/zig/scenes/catalog.zig, tools/channels.py): "pc" is a
  program port (tools); "atari st", "amiga", "atari falcon", "c64" are demos, cracktros and intros.

A "zigmachine", "system" or "unknown" cart is an original screen, a test or the OS, and no
rule can tell which: it must be in TABLE. A demo's platform is its catalog type (a Union screen:
the Union Demo's), else PLATFORM_TABLE. A cart nothing places is an ERROR (UnknownCategory),
never a catch-all folder: staging refuses the card and --check exits 1, naming the carts.
"""

from __future__ import annotations

import argparse
import functools
import re
import sys
from pathlib import Path

FPGA = Path(__file__).resolve().parent.parent
ROOT = FPGA.parent
sys.path.insert(0, str(ROOT / "tools"))
import channels  # after the path insert: the catalog parser

CATEGORIES = ("demos", "games", "tools", "tutorials", "tests", "system")
NATIVE_MK = FPGA / "cycles/native/native.mk"  # the native carts: NATIVE_TITLE_<name>
DEMO_KINDS = ("atari st", "amiga", "atari falcon", "c64")
HUB_PREFIX = "union_"  # tools/channels.py UNION_PREFIX: every one a Union Demo screen

_BY_CATEGORY = {
    "games": ("north_south", "joust", "rick_dangerous", "skystrike", "kickoff2", "bubblebobble"),
    "tools": ("st_replay", "sysinfo", "c-bench", "notepad", "gemtest"),  # the sampler, the system-information tool, the Hatari benchmark suite (apps/c/bench), the GEM 5 programs (NOTEPAD, GEMTEST: data disks, BOOT.WSM)
    "system": ("gem",),  # KOS's desktop
    "tutorials": ("tutorial", "tutorial_steps"),
    "tests": (
        "music", "badflicker", "stream", "scrolllab", "sap_test", "xm_test", "linebase_test", "tc_test", "kt_test", "sid_test", "tri_test", "desk_test", "mp3_player", "bard_sid",
        "replicants",  # REPS OLD: kept to compare with replicants_garfield
        "raytrace_f32", "polkadots_f32", "replicants_emlyn_f32",  # the FPU twins
        "hello", "hello_asm", "bench",  # native carts (cycles/native)
        # KESTREL's own feature showcases, not converted demos (Matt, 3 Nov)
        "ziggy", "chisel_v2", "blitter", "mpp_truecolor", "polkadots", "raytrace", "shapes",
    ),
    "demos": (  # the "zigmachine" screens that are shows, not tests
        "scroll", "obj", "fullscreen", "maxi", "medium_overscan", "res_switch",
        "mandelbrot", "fuji_hobbytronic", "anima", "leonard_spirit",
    ),
}  # fmt: skip
# demos/ is split by the machine a demo comes from (Matt, 7 Nov: "in carts/demos/ can you create
# sub folders: amiga, atari st, atari xl, c64..."): catalog type -> folder. No spaces on the card:
# `glass ctl load` splits its line on whitespace and the upload recipes are shell lines; the OSD
# shows '_' as a space ("ATARI ST/", fpga/glass/src/shelf_view.zig label()).
PLATFORMS = {
    "atari st": "atari_st", "amiga": "amiga", "atari falcon": "atari_falcon", "atari xl": "atari_xl",
    "c64": "c64", "zigmachine": "kestrel",  # the machine's own screens, written for it (Matt: "call it kestrel")
}  # fmt: skip
# A demo whose platform its catalog type does not give. fuji_hobbytronic stays in kestrel/: a
# screen written for the machine whose TUNE is an Atari XL SAP, not a port of an XL production.
PLATFORM_TABLE: dict[str, str] = {}
HUB = "union_demo"  # tools/shelf_meta.py HUBS: a Union screen is the Union Demo's machine's
TABLE = {tag: cat for cat, tags in _BY_CATEGORY.items() for tag in tags}
assert len(TABLE) == sum(map(len, _BY_CATEGORY.values())), "a tag is in two categories"
assert set(_BY_CATEGORY) <= set(CATEGORIES)


class UnknownCategory(ValueError):
    """A cart no rule and no TABLE entry places."""


@functools.cache
def kinds() -> dict[str, str]:
    """tag -> the catalog's machine type."""
    return {tag: kind for _, tag, kind in channels.entries()}


def native_carts() -> list[str]:
    """The native carts native.mk builds (NATIVE_TITLE_<name>)."""
    return re.findall(r"^NATIVE_TITLE_(\w+)\s*:?=", NATIVE_MK.read_text(), re.MULTILINE)


def category(tag: str) -> str:
    """The folder `tag`'s disk goes in, or UnknownCategory."""
    if tag in TABLE:
        return TABLE[tag]
    if tag.startswith(HUB_PREFIX):
        return "demos"
    kind = kinds().get(tag)
    if kind == "pc":
        return "tools"
    if kind in DEMO_KINDS:
        return "demos"
    why = f"its catalog type is {kind!r}" if kind else "it is not in the catalog"
    raise UnknownCategory(f"{tag}: no category ({why}): add it to fpga/tools/shelf_category.py TABLE")


def platform(tag: str) -> str:
    """The demos/ subfolder of demo `tag`: the machine it comes from, or UnknownCategory."""
    kind = PLATFORM_TABLE.get(tag) or kinds().get(HUB if tag.startswith(HUB_PREFIX) else tag)
    if kind in PLATFORMS:
        return PLATFORMS[kind]
    raise UnknownCategory(f"{tag}: a demo with no platform (catalog type {kind!r}): add it to PLATFORMS or PLATFORM_TABLE")


def folder(tag: str) -> str:
    """The folder `tag`'s disk goes in under CARTS/: its category, and for a demo its platform."""
    cat = category(tag)
    return f"{cat}/{platform(tag)}" if cat == "demos" else cat


def disk_path(tag: str) -> str:
    """Where the card carries `tag`'s fat disk, under CARTS/ (sd_layout.py)."""
    return f"{folder(tag)}/demo-{tag}.zmd"


def problems(tags: list[str]) -> list[str]:
    """Why each of `tags` has no category (empty: every one has)."""
    out = []
    for tag in tags:
        try:
            folder(tag)
        except UnknownCategory as e:
            out.append(str(e))
    return out


def every_tag() -> list[str]:
    """Every cart a card can carry: the catalog, the cart matrix and the native carts."""
    import shelf_meta  # here, not at the top: shelf_meta imports this module

    return sorted((set(kinds()) | set(shelf_meta.cart_tags()) | set(native_carts())) - {""})


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--check", action="store_true", help="exit 1 if any cart has no category")
    p.add_argument("--path", metavar="TAG", help="print TAG's disk path under CARTS/ (for upload scripts)")
    a = p.parse_args()
    if a.path:
        try:
            print(disk_path(a.path))
        except UnknownCategory as e:
            sys.exit(str(e))
        return 0
    tags = every_tag()
    bad = problems(tags)
    if not a.check:
        for tag in tags:
            print(f"{tag:28} {'?' if any(b.startswith(tag + ':') for b in bad) else folder(tag)}")
    print("\n".join(bad + [f"shelf_category: {len(tags)} carts, {len(bad)} without a category"]))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
