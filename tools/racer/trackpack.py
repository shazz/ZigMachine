"""The Track Kit's track pack builder (R82 M7): a folder of `.KTR` / `.KCR` / `.PAN` files -> a disk the cart boots with
them (`.zmd`), or the SD card's `HD/RACER/` folder (the cart's C:\\RACER\\). Every file is checked first by the cart's own
rules (twin_trk.py, twin_files.py: the same refusals, named as the cart names them), and the pack by the library's:

    python3 -I tools/racer/trackpack.py MYTRACKS/ --zmd racer-pack.zmd [--title "MY PACK"]   a disk: the racer cart + the files
    python3 -I tools/racer/trackpack.py MYTRACKS/ --hd SDCARD/                              SDCARD/HD/RACER/<files>

- names are 8.3, upper case: a stem of 1..8 of A-Z 0-9 _ (the list shows the stem), the extension KTR, KCR or PAN;
- a pack holds at most 15 tracks (the library lists 16 with the built-in oval; on the cart C:'s come after the disk's);
- `<TRACK>.KCR` is that track's cars, `CAR.KCR` every track's; `<TRACK>.PAN` its panorama, which the cart reads from its
  OWN DISK only, so a panorama in an `--hd` pack is refused, and one whose track is not in the pack too (it is checked
  against its track's palette: panofile.clash);
- a ZX0-packed input (zx0pack's) is depacked to be checked and stored as given; `--zmd` packs the raw ones with
  zig-out/bin/zx0pack when it is built (the cart takes either).
docs/ports/kestrel_racing/TRACK_KIT.md, "Track packs".
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from racer import twin_files, twin_trk  # noqa: E402
from racer.twin_trk import Refused  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
CART = ROOT / "site/carts/demo-racer.wasm"
ZX0PACK = ROOT / "zig-out/bin/zx0pack"
NAME = re.compile(r"^[A-Z0-9_]{1,8}\.(KTR|KCR|PAN)$")
MAX_TRACKS = 15
BUILTIN = "OVAL"  # the cart's built-in track: OVAL.KCR / OVAL.PAN dress it


class PackError(ValueError):
    """The pack (or one file of it) would not work on the cart."""


@dataclass(frozen=True)
class Item:
    name: str  # the 8.3 name on the disk or the card
    path: Path
    stored: bytes  # as given (raw or ZX0)
    raw: bytes  # depacked


def _depack(b: bytes) -> bytes:
    if b[:4] != twin_trk.ZX0_MAGIC:
        return b
    sys.path.insert(0, str(ROOT / "tools/badapple"))
    import zx0  # tools/badapple/zx0.py: the independent ZX0 reader

    try:
        return zx0.depack(b)
    except zx0.Zx0Error as e:
        raise Refused("BadPack") from e


def collect(paths: list[Path]) -> list[Item]:
    """The pack's files in order (a folder's sorted by name), named and depacked; names and duplicates checked."""
    files: list[Path] = []
    for p in paths:
        files += sorted(q for q in p.iterdir() if q.suffix.upper() in (".KTR", ".KCR", ".PAN")) if p.is_dir() else [p]
    items, seen = [], set()
    for f in files:
        name = f.name.upper()
        if not NAME.match(name):
            raise PackError(f"{f.name}: not an 8.3 name of A-Z 0-9 _ ending .KTR, .KCR or .PAN")
        if name in seen:
            raise PackError(f"{name}: twice in the pack")
        seen.add(name)
        stored = f.read_bytes()
        try:
            items.append(Item(name, f, stored, _depack(stored)))
        except Refused as e:
            raise PackError(f"{name}: refused ({e.why})") from e
    return items


def _check_one(it: Item, tracks: dict[str, bytes], hd: bool) -> None:
    stem, ext = it.name.split(".")
    if ext == "KTR":
        if twin_trk.raw_len(it.stored[:512], len(it.stored)) is None:
            raise Refused("not_track")
        twin_trk.check(it.raw)
    elif ext == "KCR":
        twin_files.car(it.raw)
        if len(it.stored) > twin_files.CAR_FILE:
            raise Refused("TooBig")
    else:
        if hd:
            raise PackError(f"{it.name}: the cart reads a panorama from its own disk only: put it in a --zmd pack")
        if stem not in tracks:
            raise PackError(f"{it.name}: no {stem}.KTR in the pack (a panorama is checked against its track's palette)")
        twin_files.pan(it.raw, tracks[stem])


def check(items: list[Item], hd: bool = False) -> list[str]:
    """Raises PackError on the first file the cart would refuse; returns the warnings (a car file for no track here)."""
    tracks = {i.name[:-4]: i.raw for i in items if i.name.endswith(".KTR")}
    if len(tracks) > MAX_TRACKS:
        raise PackError(f"{len(tracks)} tracks: the cart lists {MAX_TRACKS} besides its oval")
    if not tracks and not hd:
        raise PackError("no .KTR in the pack")
    for it in items:
        try:
            _check_one(it, tracks, hd)
        except Refused as e:
            raise PackError(f"{it.name}: the cart refuses it ({e.why})") from e
    return [f"{i.name}: no {i.name[:-4]}.KTR here: it is used only when a track of that name is on show"
            for i in items if i.name.endswith(".KCR") and i.name[:-4] not in {*tracks, "CAR", BUILTIN}]


def write_hd(items: list[Item], out: Path) -> Path:
    d = out / "HD" / "RACER"
    d.mkdir(parents=True, exist_ok=True)
    for it in items:
        (d / it.name).write_bytes(it.stored)
    return d


def _packed(blob: bytes, tmp: Path, name: str) -> bytes:
    if blob[:4] == twin_trk.ZX0_MAGIC or not ZX0PACK.is_file():
        return blob
    src, dst = tmp / f"{name}.raw", tmp / f"{name}.zx0"
    src.write_bytes(blob)
    subprocess.run([str(ZX0PACK), str(src), str(dst)], check=True, capture_output=True)
    return dst.read_bytes()


def write_zmd(items: list[Item], out: Path, title: str, cart: Path = CART) -> Path:
    if not cart.is_file():
        raise PackError(f"no {cart}: build the cart first (./build.sh --fast)")
    sys.path.insert(0, str(ROOT / "tools"))
    import mkdisk  # tools/mkdisk.py: the shelf's disk writer

    with tempfile.TemporaryDirectory() as t:
        tmp = Path(t)
        wasm = _packed(cart.read_bytes(), tmp, "cart")
        files = [(it.name, _packed(it.stored, tmp, it.name), 1) for it in items]
        if len(files) > 23:
            raise PackError(f"{len(files)} files: a disk's FAT holds 23 besides the cart")
        out.write_bytes(mkdisk.build(wasm, title, "Track Kit", "a Kestrel Racing track pack", 20260101, files))
    return out


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("inputs", nargs="+", type=Path, help="files or folders of .KTR / .KCR / .PAN")
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--zmd", type=Path, help="write a disk: the racer cart + the files")
    mode.add_argument("--hd", type=Path, help="write <dir>/HD/RACER/ (the SD card's C:\\RACER\\)")
    ap.add_argument("--title", default="RACER PACK")
    ap.add_argument("--cart", type=Path, default=CART)
    a = ap.parse_args(argv)
    try:
        items = collect(a.inputs)
        for w in check(items, hd=a.hd is not None):
            print(f"trackpack: warning: {w}", file=sys.stderr)
        out = write_hd(items, a.hd) if a.hd else write_zmd(items, a.zmd, a.title, a.cart)
    except (PackError, OSError) as e:
        print(f"trackpack: {e}", file=sys.stderr)
        return 1
    print(f"trackpack: {out}: " + " ".join(i.name for i in items))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
