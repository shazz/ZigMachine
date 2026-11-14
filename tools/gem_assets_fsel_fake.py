"""A MADE-UP SELECTOR manifest entry for tools/gem_assets_conv_test.py: every object the
converter's gem_assets_fsel.py looks for, at invented coordinates (nothing of TOS's tree).
The drive buttons sit in a group at (200, 40), so the converter must add the parent's offset;
the DRIVE: label carries one leading blank, so the converter must step over it."""

from __future__ import annotations


def _o(depth: int, name: str, rect: list[int], text: str = "", ty: str = "G_BOX") -> dict:
    return {"depth": depth, "name": name, "rect": rect, "text": text, "type": ty}


def made_up_selector() -> dict:
    objs = [
        _o(0, "", [0, 0, 300, 150]),
        _o(1, "FLABEL", [10, 3, 200, 8], "PATH", "G_TEXT"),
        _o(1, "", [8, 12, 80, 8], "Directory:", "G_STRING"),
        _o(1, "FDIRECTO", [8, 22, 280, 8]),
        _o(1, "", [8, 32, 80, 8], "Selection:", "G_STRING"),
        _o(1, "FSELECTI", [90, 32, 96, 8]),
        _o(1, "FSDRIVE", [190, 32, 56, 8], " DRIVE:", "G_STRING"),
        _o(1, "FCLSBOX", [20, 44, 16, 8]),
        _o(1, "FTITLE", [36, 44, 140, 10]),
        _o(1, "DRVBOX", [200, 40, 80, 100]),
        _o(2, "DRIVEA", [1, 2, 30, 8]),
        _o(2, "DRIVEB", [41, 2, 30, 8]),
        _o(2, "DRIVEC", [1, 14, 30, 8]),
        _o(1, "FILEBOX", [20, 54, 150, 80]),
        _o(2, "F1NAME", [10, 6, 120, 8]),
        _o(2, "F2NAME", [10, 14, 120, 8]),
        _o(1, "SCRLBAR", [170, 54, 20, 80]),
        _o(2, "FUPAROW", [0, 0, 20, 12]),
        _o(2, "FSVSLID", [0, 12, 20, 56]),
        _o(2, "FDNAROW", [0, 68, 20, 12]),
        _o(1, "OK", [60, 138, 70, 8]),
        _o(1, "CANCEL", [170, 138, 70, 8]),
    ]
    return {"file": "aes340_tos4/sel.png", "kind": "component", "tree": "SELECTOR", "mode": "st_medium", "objects": objs}


# What the converter must make of it (the CHECK in gem_assets_conv_test.py).
FSEL_CHECK = """    try eq(@as(usize, 1), ga.selectors.len);
    const fs = ga.selectors[0];
    try eq(@as(u8, 8), fs.ch);
    try eq(@as(i16, 201), fs.drive[0]); // DRIVEA in its group: 200 + 1
    try eq(@as(i16, 42), fs.drive[1]);
    try eq(@as(i16, 12), fs.dy);
    try eq(@as(i16, 198), fs.drive_label[0]); // " DRIVE:" drawn without its blank
    try eq(@as(i16, 8), fs.pitch);
    try eq(@as(i16, 66), fs.track[1]); // FSVSLID in the scroll bar: 54 + 12
"""
