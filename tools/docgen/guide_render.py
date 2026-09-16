"""Assembles docs/ZIGMACHINE_GUIDE.html from the parsed sources and the prose."""
from __future__ import annotations

import re
from datetime import date

from . import ROOT, esc, render_markdown_file
from .guide_content import EXAMPLES, INTRO
from .guide_theme import CSS, TEMPLATE
from .zig_parse import Item, parse_consts, parse_externs, parse_struct_methods

GEOMETRY_RE = r"(?:WIDTH|HEIGHT|NB_PLANES|PHYSICAL_\w+|RASTER_\w+|MEDIUM_\w+|HORIZONTAL_\w+|VERTICAL_\w+|STRIDE_\w+)"

# The groups whose lengths are summed into the header's "N library methods" and
# "N constants/registers" counts.
METHOD_KEYS = ("lfb", "zos", "blitter", "gui", "wm", "menubar", "dialog", "desktop", "mesh")
CONST_KEYS = ("geometry", "modes", "regs", "blit_regs", "blit_ctl")


def render_items(items: list[Item]) -> str:
    rows = []
    for it in items:
        doc = f'<div class="doc">{esc(it.doc)}</div>' if it.doc else ""
        rows.append(f'<div class="item"><code class="sig">{esc(it.sig)}</code>{doc}</div>')
    return "\n".join(rows)


def render_consts(items: list[Item]) -> str:
    rows = ["<table><thead><tr><th>Name</th><th>Value</th><th>Meaning</th></tr></thead><tbody>"]
    for it in items:
        rows.append(
            f"<tr><td><code>{esc(it.name)}</code></td>"
            f"<td><code>{esc(it.sig)}</code></td><td>{esc(it.doc)}</td></tr>"
        )
    rows.append("</tbody></table>")
    return "\n".join(rows)


def render_examples() -> str:
    out = []
    for title, code in EXAMPLES:
        out.append(f'<h3>{esc(title)}</h3><pre class="code">{esc(code)}</pre>')
    return "\n".join(out)


def parse_sources() -> dict[str, list[Item]]:
    """Every generated reference group, parsed from the Zig sources it documents."""
    sdk = ROOT / "machine" / "sdk"
    mm = sdk / "memmap.zig"
    zigos = ROOT / "libs" / "zig" / "zigos.zig"
    gem_gui = ROOT / "rom" / "gem" / "gui.zig"
    return {
        "geometry": parse_consts(mm, GEOMETRY_RE),
        "modes": parse_consts(mm, r"(?:RES_\w+|FB_MODE_\w+)"),
        "regs": parse_consts(mm, r"REG_\w+"),
        "blit_regs": parse_consts(mm, r"BLIT_[A-Z_]+"),
        "blit_ctl": parse_consts(mm, r"(?:CON_\w+|MT_\w+|BLIT_CMD_\w+|BLIT_STATUS_\w+)"),
        "abi": parse_externs(sdk / "hardware.zig"),
        "lfb": parse_struct_methods(zigos, "LogicalFB"),
        "zos": parse_struct_methods(zigos, "ZigOS"),
        "blitter": parse_struct_methods(ROOT / "libs" / "zig" / "blitter.zig", "Blitter"),
        "gui": parse_struct_methods(gem_gui, "Gui"),
        "wm": parse_struct_methods(gem_gui, "Wm"),
        "menubar": parse_struct_methods(gem_gui, "MenuBar"),
        "dialog": parse_struct_methods(gem_gui, "Dialog"),
        "desktop": parse_struct_methods(ROOT / "rom" / "gem" / "gem.zig", "Desktop"),
        "mesh": parse_struct_methods(ROOT / "libs" / "zig" / "utils" / "obj_loader.zig", "Mesh"),
    }


def groups(s: dict[str, list[Item]]) -> list[tuple[str, str]]:
    """The guide's sections, in reading order."""
    return [
        # Newcomers first: build a screen before reading the reference.
        ("Tutorial — your first screen (Zig, C, Rust)", render_markdown_file("docs/TUTORIAL.md")),
        ("Geometry & resolution", render_consts(s["geometry"])),
        ("Resolution & plane modes", render_consts(s["modes"])),
        ("Video registers", render_consts(s["regs"])),
        ("Blitter registers", render_consts(s["blit_regs"])),
        ("Blitter commands / control / minterms", render_consts(s["blit_ctl"])),
        ("HW ABI — machine exports", render_items(s["abi"])),
        ("Disk / cart format + boot sectors", render_markdown_file("docs/FLOPPY_DISK.md")),
        ("Music — SNDH player (Zig, C, Rust)", render_markdown_file("docs/MUSIC.md")),
        ("ZigOS — LogicalFB (a plane)", render_items(s["lfb"])),
        ("ZigOS — ZigOS (the OS)", render_items(s["zos"])),
        ("ZigOS — Blitter (2D coprocessor)", render_items(s["blitter"])),
        ("ZigOS — GUI toolkit (Gui)", render_items(s["gui"])),
        ("ZigOS — Window manager (Wm)", render_items(s["wm"])),
        ("ZigOS — Menu bar (MenuBar)", render_items(s["menubar"])),
        ("ZigOS — Dialog (modal alert / file selector)", render_items(s["dialog"])),
        ("ZigGEM ROM — Desktop (boot shell / app launcher)", render_items(s["desktop"])),
        ("ZigOS — OBJ loader (Mesh)", render_items(s["mesh"])),
    ]


def _counts(s: dict[str, list[Item]]) -> str:
    methods = sum(len(s[k]) for k in METHOD_KEYS)
    consts = sum(len(s[k]) for k in CONST_KEYS)
    return f"{len(s['abi'])} ABI exports · {methods} library methods · {consts} constants/registers"


def build() -> str:
    s = parse_sources()
    gs = groups(s)
    nav = "\n".join(f'<a href="#{i}">{esc(t)}</a>' for i, (t, _) in enumerate(gs))
    sections = "\n".join(
        f'<section id="{i}"><h2>{esc(t)}</h2>{body}</section>' for i, (t, body) in enumerate(gs)
    )
    return TEMPLATE.format(
        css=CSS,
        date=date.today().isoformat(),
        counts=_counts(s),
        intro=INTRO,
        nav=nav,
        examples=render_examples(),
        sections=sections,
    )


GENERATED_LINE = re.compile(r"Generated \d{4}-\d{2}-\d{2} by tools/gen_docs\.py")


def undated(text: str) -> str:
    """The guide minus its generation date, which changes every day by itself."""
    return GENERATED_LINE.sub("Generated by tools/gen_docs.py", text)
