"""Write shelf.txt: what the glass's OSD shows about each cart (docs/FPGA_GLASS.md).

    uv run python tools/shelf_meta.py [--out DIR] [--check]

One line a disk, tab-separated: FILE, TITLE, GROUP, YEAR, TYPE, DESCRIPTION
(fpga/glass/src/meta.zig reads it). Nothing is typed twice; each field comes
from where the repo already keeps it:

- TITLE and TYPE: apps/zig/scenes/catalog.zig (tools/channels.py's parser, so
  the same 22-character cap and machine types apply), except where OVERRIDES
  names the cart (GEM's catalog title is the menu's "EXIT TO GEM");
- DESCRIPTION: the cart matrix's comment in build.zig ("61 - vEctRoniX / VEX
  2025, the GTA VI cracktro ..."), else cart.zig's comment on the scene's
  import, else the first line of the scene's header comment;
- GROUP: the part before " / " in that description, when it has one;
- YEAR: the first year (1985..2029) in the description or the header's first
  paragraph.

A field nobody wrote down stays empty, and --check lists those carts, so a gap
is visible rather than invented. Text is folded to ASCII: the OSD draws the
ST's 8-bit font, not UTF-8.
"""

from __future__ import annotations

import argparse
import re
import sys
import unicodedata
from pathlib import Path

FPGA = Path(__file__).resolve().parent.parent
ROOT = FPGA.parent
sys.path.insert(0, str(ROOT / "tools"))
import channels  # after the path insert: the catalog parser

BUILD_ZIG = ROOT / "build.zig"
CART_ZIG = ROOT / "apps/zig/cart.zig"
SCENES = ROOT / "apps/zig"
FILE = "shelf.txt"
YEAR = re.compile(r"\b(198[5-9]|199\d|20[0-2]\d)\b")
FOLD = {"—": "-", "–": "-", "·": "-", "‘": "'", "’": "'", "“": '"', "”": '"'}
# The one place a field is typed here: where the catalog's TITLE is the browser menu's verb, not
# the cart's name (catalog.zig calls GEM "EXIT TO GEM", its menu entry), or the source names no
# group or year. tag -> (title, group, year); an empty field keeps what the repo says.
OVERRIDES = {
    "gem": ("GEM DESKTOP", "Digital Research", "1985"),  # TOS 1.00's desktop (rom/gem/desktop/about.zig)
    "st_replay": ("", "Microdeal", ""),  # its description: "a homage to Microdeal's 8-bit sampler"
}


def ascii_text(s: str) -> str:
    """One OSD-safe line: no tabs or newlines, typographic marks folded, accents dropped."""
    s = "".join(FOLD.get(c, c) for c in s)
    s = unicodedata.normalize("NFKD", s).encode("ascii", "ignore").decode()
    return " ".join(s.split())


def matrix_comments() -> dict[str, str]:
    """tag -> the comment after it in build.zig's cart_names ("NN - text")."""
    text = BUILD_ZIG.read_text()
    body = text[text.index("const cart_names") :]
    body = body[: body.index("};")]
    out = {}
    for line in body.splitlines():
        m = re.match(r'\s*"demo-([^"]+)",\s*//\s*\d+\s*[—-]+\s*(.+)', line)
        if m:
            out[m.group(1)] = m.group(2).strip()
    return out


def scene_files() -> list[tuple[str, str]]:
    """cart index -> (scene path, cart.zig comment), in switch order."""
    text = CART_ZIG.read_text()
    rows = re.findall(r'^\s*(\d+)\s*=>\s*@import\("([^"]+)"\),?[ \t]*(?://[ \t]*(.*))?$', text, re.M)
    return [(path, comment.strip()) for _, path, comment in sorted(rows, key=lambda r: int(r[0]))]


def cart_tags() -> list[str]:
    """The cart matrix's tags, index-aligned with cart.zig ("" for an excluded slot)."""
    text = BUILD_ZIG.read_text()
    body = text[text.index("const cart_names") :]
    names = re.findall(r'"(demo(?:-[^"]*)?)"', body[: body.index("};")])
    return [n.removeprefix("demo-") if n != "demo" else "" for n in names]


def header(scene: Path) -> list[str]:
    """The first real paragraph of the scene's leading comment: not a rule line,
    not a one-word section label ("Imports")."""
    para: list[str] = []
    for raw in scene.read_text().splitlines():
        if not raw.startswith("//"):
            break
        line = raw[2:].strip()
        if line and set(line) != {"-"}:
            para.append(line)
            continue
        if len(" ".join(para).split()) > 3:
            return para
        para = []
    return para if len(" ".join(para).split()) > 3 else []


def strip_name(desc: str, name: str) -> str:
    """'STNICCC 2000 - the flat-shaded flight ...' -> 'the flat-shaded flight ...'"""
    m = re.match(r"(.{2,40}?)\s+[\u2014-]+\s+(.*)", desc)
    if m and m.group(1).upper() in name.upper() + " " + name.upper().replace(" ", ""):
        return m.group(2)[:1].upper() + m.group(2)[1:]
    return desc


def group_of(desc: str) -> str:
    """'The Exceptions / The B.I.G. Demo ...' -> 'The Exceptions'; only a leading,
    capitalised name before the first ' / ' counts."""
    head = desc.split(" / ")[0] if " / " in desc else ""
    return head if 0 < len(head) <= 30 and head[0].isupper() and "," not in head else ""


def describe(tag: str, name: str, comments: dict[str, str], scenes: dict[str, tuple[str, str]]) -> tuple[str, ...]:
    """(group, year, description) for one tag."""
    path, cart_comment = scenes.get(tag, ("", ""))
    head = header(SCENES / path) if path and (SCENES / path).exists() else []
    first = re.split(r"(?<=[.:])\s", " ".join(head))[0] if head else ""
    desc = comments.get(tag) or cart_comment or strip_name(first, name)
    group = group_of(desc)
    year = next((m.group(1) for s in (desc, " ".join(head)) if (m := YEAR.search(s))), "")
    return ascii_text(group), year, ascii_text(desc)


def records(tags: list[str] | None = None) -> list[tuple[str, ...]]:
    comments = matrix_comments()
    scenes = {t: s for t, s in zip(cart_tags(), scene_files(), strict=False) if t}
    out = []
    for name, tag, kind in channels.entries():
        if tags is not None and tag not in tags:
            continue
        group, year, desc = describe(tag, name, comments, scenes)
        title, group, year = (
            o or d for o, d in zip(OVERRIDES.get(tag, ("", "", "")), (name, group, year), strict=True)
        )
        out.append((f"demo-{tag}.zmd", ascii_text(title), group, year, kind, desc))
    return out


def write(dest: Path, tags: list[str] | None = None) -> Path:
    rows = records(tags)
    head = "# shelf.txt: written by fpga/tools/shelf_meta.py. FILE TITLE GROUP YEAR TYPE DESCRIPTION, tab-separated.\n"
    dest.mkdir(parents=True, exist_ok=True)
    (dest / FILE).write_text(head + "".join("\t".join(r) + "\n" for r in rows))
    return dest / FILE


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--out", type=Path, default=FPGA / "build/glass/sd/zigmachine")
    p.add_argument("--check", action="store_true", help="list carts with no group, year or description; write nothing")
    a = p.parse_args()
    rows = records()
    gaps = [f"{r[0]}: no {', '.join(n for n, v in zip(('group', 'year', 'description'), r[2:4] + r[5:]) if not v)}"
            for r in rows if not (r[2] and r[3] and r[5])]  # fmt: skip
    if a.check:
        print("\n".join(gaps) + f"\nshelf_meta: {len(rows)} carts, {len(gaps)} with a gap")
        return
    print(f"shelf_meta: {write(a.out)} ({len(rows)} carts, {len(gaps)} with a gap)")


if __name__ == "__main__":
    main()
