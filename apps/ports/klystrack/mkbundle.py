"""Build a klystron theme bundle (klystron/src/util/bundle.c's format) the way upstream's Makefile does
(theme_defs: colors.txt, bevel/vu/analyzor/catometer/cursor images, and the font/, font7x6/, tiny/ folders as
nested 8x8.fnt / 7x6.fnt / 4x6.fnt bundles; logo.* goes nowhere upstream, a typo, and icon.* is skipped here:
the cart has no window icon). makebundle.c is a native tool; this is its format in Python.

    "bnd!"  u32 flags (0)  u32 n_files  { name NUL, u32 size } x n  then the files' bytes in that order
    (little-endian, sizes > 0 only)

    python3 mkbundle.py <theme dir> <out>"""
import struct, sys
from pathlib import Path

def bundle(entries):
    head = b"bnd!" + struct.pack("<II", 0, len(entries))
    head += b"".join(name.encode() + b"\0" + struct.pack("<I", len(data)) for name, data in entries)
    return head + b"".join(data for _, data in entries)

def folder(d):
    return bundle([(p.name, p.read_bytes()) for p in sorted(d.iterdir()) if p.is_file() and p.stat().st_size > 0])

def theme(src):
    entries = []
    for p in sorted(src.iterdir()):
        stem = p.name.split(".")[0]
        if p.is_file() and (p.name == "colors.txt" or stem in ("bevel", "vu", "analyzor", "catometer", "cursor")):
            entries.append((p.name, p.read_bytes()))
    for sub, name in (("font", "8x8.fnt"), ("font7x6", "7x6.fnt"), ("tiny", "4x6.fnt")):
        if (src / sub).is_dir():
            entries.append((name, folder(src / sub)))
    return bundle(entries)

if __name__ == "__main__":
    src, out = Path(sys.argv[1]), Path(sys.argv[2])
    Path(out).write_bytes(theme(src))
