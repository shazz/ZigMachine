"""The guide's sections, in reading order, grouped the way the rail shows them.

`title` is the anchor: slug(title) is the section id, and deep links into the
guide depend on it (the tutorial's register callouts, index.html), so a title
changes only when the link is meant to. `short` and `sub` are what the page
shows; `group` is the rail heading and the section's eyebrow.
"""
from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class Sec:
    group: str
    title: str
    short: str
    sub: str
    kind: str  # "consts" (a table), "items" (an API list) or "md" (a markdown chapter)
    src: str  # the parse_sources() key, or the markdown path for "md"
    prefix: str = ""  # id prefix of each API entry: LogicalFB.setScroll


SECTIONS: list[Sec] = [
    Sec("Machine", "Geometry & resolution", "Geometry", "raster, window and border sizes", "consts", "geometry"),
    Sec("Machine", "Resolution & plane modes", "Plane modes", "FB_MODE_* and RES_*", "consts", "modes"),
    Sec("Machine", "Video registers", "Video registers", "the sealed video block", "consts", "regs"),
    Sec("Machine", "Blitter registers", "Blitter registers", "OFF_BLIT + …", "consts", "blit_regs"),
    Sec("Machine", "Blitter commands / control / minterms", "Blitter control", "commands, CON_* bits, minterms",
        "consts", "blit_ctl"),
    Sec("Machine", "HW ABI — machine exports", "HW ABI", "what machine-*.wasm exports", "items", "abi"),
    Sec("Machine", "Memory management", "Memory", "cart RAM, the RAM arena, VRAM", "md", "docs/MEMORY.md"),
    Sec("Formats", "Disk / cart format + boot sectors", "Disk & cart format", "docs/FLOPPY_DISK.md", "md",
        "docs/FLOPPY_DISK.md"),
    Sec("Formats", "Music — SNDH player (Zig, C, Rust)", "Music", "docs/MUSIC.md", "md", "docs/MUSIC.md"),
    Sec("ZigOS", "ZigOS — LogicalFB (a plane)", "LogicalFB", "a plane", "items", "lfb", "LogicalFB"),
    Sec("ZigOS", "ZigOS — ZigOS (the OS)", "ZigOS", "the OS", "items", "zos", "ZigOS"),
    Sec("ZigOS", "ZigOS — Blitter (2D coprocessor)", "Blitter", "2D coprocessor", "items", "blitter", "Blitter"),
    Sec("ZigOS", "ZigOS — OBJ loader (Mesh)", "Mesh", "Wavefront OBJ loader", "items", "mesh", "Mesh"),
    Sec("GEM", "ZigOS — GUI toolkit (Gui)", "Gui", "immediate-mode widgets", "items", "gui", "Gui"),
    Sec("GEM", "ZigOS — Window manager (Wm)", "Wm", "window manager", "items", "wm", "Wm"),
    Sec("GEM", "ZigOS — Menu bar (MenuBar)", "MenuBar", "menu bar", "items", "menubar", "MenuBar"),
    Sec("GEM", "ZigOS — Dialog (modal alert / file selector)", "Dialog", "modal alert, file selector", "items",
        "dialog", "Dialog"),
    Sec("GEM", "ZigGEM ROM — Desktop (boot shell / app launcher)", "Desktop", "boot shell, app launcher",
        "items", "desktop", "Desktop"),
]
