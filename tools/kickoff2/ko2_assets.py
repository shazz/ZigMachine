#!/usr/bin/env python3
"""Kick Off 2 (Go remake) -> ZigMachine cart assets converter.

Inputs  : /tmp/opencode/kickoff2/assets/original/{raw,images}
Outputs : apps/zig/assets/screens/kickoff2/

Sprite sheets stay INDEXED (source palette position preserved wherever it is
meaningful, e.g. kit shirt/shorts slots 4/6 on 'a' sheets, 2/5 on 'b' sheets)
mapped onto the cart's shared 16-colour match palette:

    0 transparent      1 dark surround     2 grass mid      3 grass dark
    4 pitch line white 5 skin              6 shirt A        7 shorts A
    8 shirt B          9 shorts B         10 dark (hair/boot)
   11 white            12 ball shadow ink 13 net / light grey
   14 crowd 1          15 crowd 2

Shirt/short entries 6/7/8/9 are POSITIONS only: their RGB is set at runtime
from the kit colour table (kit.go kitColors) for the match's two teams.

Title screen gets its own 16-colour palette (the front page runs before the
match plane is reused).

Sounds: the whole `expsound` Paula bank is re-rendered to 12 kHz signed 8-bit
mono (the ZigMachine audio ring's own rate) and concatenated into sounds.bin
with a tiny header; the Zig player runs it through zg.audioStreamStart/feed.
"""
import os
import struct
import sys
import wave

from PIL import Image

SRC = os.environ.get("KO2_SRC", "/tmp/opencode/kickoff2/assets/original")
DST = os.environ.get(
    "KO2_DST",
    os.path.join(os.path.dirname(__file__), "..", "..", "apps", "zig", "assets", "screens", "kickoff2"),
)
RING_RATE = 12000


# ---------------------------------------------------------------- ILBM decode
def decode_ilbm(path):
    d = open(path, "rb").read()
    assert d[:4] == b"FORM" and d[8:12] == b"ILBM", path
    off = 12
    bmhd = None
    cmap = None
    body = None
    end = len(d)
    while off + 8 <= end:
        tag = d[off : off + 4]
        ln = struct.unpack(">I", d[off + 4 : off + 8])[0]
        payload = d[off + 8 : off + 8 + ln]
        if ln & 1:
            payload += b"\0"
        if tag == b"BMHD":
            bmhd = payload
        elif tag == b"CMAP":
            cmap = payload
        elif tag == b"BODY":
            body = payload
        off += 8 + ln
    w, h, _x, _y, planes, mask, comp, _pad = struct.unpack(">HHhhBBBB", bmhd[:12])
    transparent = struct.unpack(">H", bmhd[12:14])[0]
    rowb = ((w + 15) // 16) * 2
    planar = bytearray(rowb * planes * h)

    if comp == 0:
        planar[:] = body[: len(planar)]
    else:
        # ByteRun1
        src = 0
        dst = 0
        while dst < len(planar) and src < len(body):
            n = body[src]
            src += 1
            if n < 128:
                n += 1
                planar[dst : dst + n] = body[src : src + n]
                src += n
                dst += n
            elif n > 128:
                n = 257 - n
                v = body[src]
                src += 1
                planar[dst : dst + n] = bytes([v]) * n
                dst += n
    pal = []
    for i in range(len(cmap) // 3):
        r, g, b = cmap[i * 3 : i * 3 + 3]
        pal.append((r >> 4, g >> 4, b >> 4))  # ST nibble space (x17 == x16*17/16)
    rows = []
    for y in range(h):
        rows.append(
            [planar[(y * rowb * planes) + p * rowb + x] for p in range(planes) for x in range(rowb)]
        )
    indices = bytearray(w * h)
    for y in range(h):
        base = y * rowb * planes
        for x in range(w):
            bi = x >> 3
            bit = 0x80 >> (x & 7)
            v = 0
            for p in range(planes):
                if planar[base + p * rowb + bi] & bit:
                    v |= 1 << p
            indices[y * w + x] = v
    mask_rowb = rowb + 2 if mask == 1 else 0  # mask plane gets an even-row pad
    return {
        "w": w,
        "h": h,
        "pal": pal,
        "indices": indices,
        "mask": mask,
        "transparent": transparent,
        "comp": comp,
        "rowb": rowb,
        "body": body,
    }


def classify(rgb):
    """Rough palette-position classifier for sprite palettes."""
    r, g, b = rgb
    if (r, g, b) == (0, 0, 0):
        return "black"
    if r >= 13 and g >= 13 and b >= 13:
        return "white"
    if r >= 14 and g >= 10 and b >= 9 and not (r == b and g == r):
        return "skin"  # (15,13,12)-ish: bright r, mid g/b, not grey
    if r <= 3 and g <= 3 and b <= 3:
        return "black"
    if max(r, g, b) <= 6:
        return "dark"
    return "mid"


# ------------------------------------------------------------------- helpers
def emit(path, data):
    with open(path, "wb") as f:
        f.write(data)
    print(f"{os.path.relpath(path, DST):24s} {len(data):7d} bytes")


def png_palette_indices(path, pal):
    """Quantize an arbitrary PNG onto the fixed 16-entry palette."""
    im = Image.open(path).convert("RGB")
    out = bytearray()
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b = px[x, y]
            best, bi = 1 << 30, 0
            for i, (pr, pg, pb) in enumerate(pal):
                d = (r - pr) * (r - pr) + (g - pg) * (g - pg) + (b - pb) * (b - pb)
                if d < best:
                    best, bi = d, i
            out.append(bi)
    return out, im.size


# ------------------------------------------------------------------ main work
def convert_sheets():
    # ------------------------------------------------------------------
    # Source palette (all raw files share it):
    #   0 transparent green, 1 black/detail, 2 shirt-B slot, 3 skin,
    #   4 shirt-A slot, 5 shorts-B/referee-white slot, 6 shorts-A slot,
    #   7 dark-green outline/shadow
    # Cart palette:
    #   0 transparent, 1 dark surround, 2 grass mid, 3 grass dark,
    #   4 pitch line white, 5 skin, 6 shirt A, 7 shorts A, 8 shirt B,
    #   9 shorts B, 10 dark (hair/boot/outline), 11 white (gear),
    #   12 keeper jersey, 13 light grey (net/marks), 14 crowd 1, 15 crowd 2
    # ------------------------------------------------------------------
    KEEPER_JERSEY = 12

    def sheet_map(shirt, shorts):
        m = {
            0: 0, 1: 10, 7: 10,
            3: 5, 5: 11, 2: 11, 4: 11, 6: 11,
        }
        m[shirt] = 6  # replaced per source layout below
        return m, shirt, shorts

    names = []
    for fname, shirt, shorts in (("style1a.iff", 4, 6), ("style1b.iff", 2, 5)):
        d = decode_ilbm(f"{SRC}/raw/{fname}")
        m = {
            0: 0, 1: 10, 3: 5, 7: 10, 5: 11, 6: 11, 2: 11, 4: 11,
            shirt: 6 if "a" in fname else 8,
            shorts: 7 if "a" in fname else 9,
        }
        m[0] = 0
        img = d["indices"]
        out = bytearray(m[v] for v in img)
        assert (d["w"], d["h"]) == (320, 193), (fname, d["w"], d["h"])
        emit(os.path.join(DST, "players_a.bin" if "a" in fname else "players_b.bin"), bytes(out))
        names.append(f"{fname}: pal={d['pal']}")
    keeper = decode_ilbm(f"{SRC}/raw/keeper.iff")
    km = {0: 0, 1: KEEPER_JERSEY, 3: 5, 7: 10, 2: 11, 4: 11, 5: 11, 6: 11}
    out = bytearray(km[v] for v in keeper["indices"])
    print("keeper.iff", keeper["w"], keeper["h"], keeper["pal"])
    emit(os.path.join(DST, "keeper.bin"), bytes(out))
    referee = decode_ilbm(f"{SRC}/raw/referee.iff")
    rm = {0: 0, 1: 10, 3: 5, 7: 10, 2: 11, 4: 11, 5: 11, 6: 11}
    out = bytearray(rm[v] for v in referee["indices"])
    print("referee.iff", referee["w"], referee["h"], referee["pal"])
    emit(os.path.join(DST, "referee.bin"), bytes(out))
    ball = decode_ilbm(f"{SRC}/raw/ball.iff")
    print("ball.iff", ball["w"], ball["h"], ball["pal"], "transparent", ball["transparent"])
    bm = {0: 0, 1: 10, 3: 11, 7: 10, 2: 11, 4: 11, 5: 11, 6: 11}
    out = bytearray(bm[v] for v in ball["indices"])
    emit(os.path.join(DST, "ball.bin"), bytes(out))
    report_path = os.path.join(DST, "cant_regen.manifest.txt")
    emit(report_path, ("\n".join(names) + "\n").encode())


def convert_title():
    im = Image.open(f"{SRC}/images/title.png").convert("RGB").crop((0, 0, 320, 200))
    cols = sorted(im.getcolors(10 ** 6), reverse=True)
    # build a fixed 16-colour title palette via median cut approximation:
    # keep the 16 most popular colours.
    pal = []
    for n, rgb in cols:
        if all(sum(abs(a - b) for a, b in zip(rgb, p)) > 24 for p in pal):
            pal.append(rgb)
        if len(pal) >= 16:
            break
    if len(pal) < 16:
        pal.extend([(0, 0, 0)] * (16 - len(pal)))
    out = bytearray()
    px = im.load()
    for y in range(im.height):
        for x in range(im.width):
            r, g, b = px[x, y]
            best, bi = 1 << 30, 0
            for i, (pr, pg, pb) in enumerate(pal):
                d = (r - pr) * (r - pr) + (g - pg) * (g - pg) + (b - pb) * (b - pb)
                if d < best:
                    best, bi = d, i
            out.append(bi)
    assert (im.width, im.height) == (320, 200), (im.width, im.height)
    emit(os.path.join(DST, "title.bin"), bytes(out))
    print("title pal:", pal)


def resample(pcm, period):
    src_rate = 3546895.0 / period
    n_out = int(round(len(pcm) * RING_RATE / src_rate))
    out = bytearray(n_out)
    for i in range(n_out):
        t = i * src_rate / RING_RATE
        j = int(t)
        frac = t - j
        a = pcm[j] if j < len(pcm) else 0
        b = pcm[j + 1] if j + 1 < len(pcm) else last(a)
        out[i] = max(-128, min(127, int(round((a + (b - a) * frac)))))
    return bytes(out)


def last(v):
    return v


def convert_sounds():
    data = open(f"{SRC}/raw/expsound", "rb").read()
    footer = struct.unpack(">I", data[:4])[0]
    count = struct.unpack(">H", data[footer : footer + 2])[0]
    samples = []
    for i in range(count):
        at = struct.unpack(">I", data[footer + 2 + i * 4 : footer + 6 + i * 4])[0]
        period, size = struct.unpack(">HI", data[at : at + 6])
        dma = size & ~1
        pcm = data[at + 6 : at + 6 + dma]
        rate = 3546895 / period
        samples.append({"i": i, "rate": rate, "pcm": pcm})
    # Curated cart bank: the kick/whistle/contact/bounce set the curated match
    # uses. Drops the multi-second crowd roars (samples 10..13) that a silent
    # Stadium can't mute tastefully (they'd dominate the one-shot ring).
    KEPT = [0, 1, 2, 3, 6, 7, 8, 9, 14, 15, 16]
    kept = [samples[i] for i in KEPT]
    out = bytearray()
    out += struct.pack("<HH", len(kept), RING_RATE)
    blobs = []
    for s in kept:
        blob = resample(s["pcm"], int(3546895 / s["rate"]))
        blobs.append(blob)
        print(f"  sample {s['i']:3d} rate {s['rate']:7.0f} len {len(blob):6d}")
    for b in blobs:
        out += struct.pack("<I", len(b))
    for b in blobs:
        out += b
    emit(os.path.join(DST, "sounds.bin"), bytes(out))
    emit(os.path.join(DST, "sounds.txt"), ("\n".join(f"{i}->{n}" for i, n in zip(KEPT, range(len(KEPT)))) + "\n").encode())


def convert_tactics():
    """Tactic files: 10 players x 20 targets, u16 BE pairs (DecodeTactic)."""
    out_lines = [
        "// Generated by tools/kickoff2/ko2_assets.py from the original .tac files",
        "// (10 players x 20 targets, u16 BE pairs). Player 0 is the keeper.",
        "pub const Tactic = struct { targets: [10][20][2]u16 };",
        ""]
    for name in ("balanced", "4-4-2"):
        data = open(f"{SRC}/raw/{name}.tac" if name == "442" else f"{SRC}/raw/{name}.tac", "rb").read()
        assert len(data) >= 800
        out_lines.append(f"pub const tactic_{name.replace("-","")} = Tactic{{ .targets = .{{")
        for i in range(10):
            row = []
            for j in range(20):
                off = i * 80 + j * 4
                x, y = struct.unpack(">HH", data[off : off + 4])
                row.append(f".{{ {x}, {y} }}")
            out_lines.append("    .{ " + ", ".join(row) + " },")
        out_lines.append("} };")
        out_lines.append("")
    emit(os.path.join(DST, "tactics.zig"), ("\n".join(out_lines) + "\n").encode())


NOR_PAL = ((0, 0, 0), (0, 160, 0), (48, 144, 0), (0, 128, 0),
           (192, 208, 176), (144, 144, 144), (112, 112, 112), (0, 192, 240))
ART_PAL = ((0, 0, 0), (64, 160, 0), (0, 160, 0), (0, 144, 0),
           (240, 240, 240), (144, 144, 144), (0, 96, 208), (0, 176, 240))


def convert_pitch_art(surface: str = "nor"):
    """The ripped pitch bitmap (render.go drawPitch draws whole 1280x1536 art).

    surface: "nor" = normal grass (the friendly default, Pitch**: Normal */
    covers whole 1280x1536 art; display slots via MATCH_PAL/ART_SLOT = LUT
    [0,1,2,3,4,13,14,15] over the surface's own 8-colour palette below.

    Only 8 flat colours, patterned in 16x16 tiles: banked as a unique-tile
    cache (slots x 128 bytes at 4 bpp, 2 px/byte high-nibble-first)
    plus an 80x96 u8 tile map. Emitted layout:

        u16 tileCount (LE)
        tiles: tileCount x 128 bytes  (16 rows x 2 half-bytes x 8 px x 2 px/byte)
        map:   96 rows x 80 cols      (art y first, then art x)

    Nibble palette order (== art colours):
        0 (0,0,0)      1 (64,160,0)    2 (0,160,0)    3 (0,144,0)
        4 (240,240,240) 5 (144,144,144) 6 (0,96,208)  7 (0,176,240)
    """
    pal = NOR_PAL if surface == "nor" else ART_PAL
    col = list(pal)
    im = Image.open(f"{SRC}/images/pitch.{surface}.png").convert("RGB")
    assert im.size == (1280, 1536), im.size
    idx = {c: i for i, c in enumerate(col)}
    px = im.load()
    tiles = {}
    the_map = bytearray()
    for ty in range(96):
        for tx in range(80):
            blk = bytearray()
            for j in range(16):
                for half in range(2):
                    for pair in range(4):
                        v0 = idx.get(px[tx * 16 + half * 8 + pair * 2, ty * 16 + j])
                        v1 = idx.get(px[tx * 16 + half * 8 + pair * 2 + 1, ty * 16 + j])
                        assert v0 is not None and v1 is not None, ((tx, ty), (j, half, pair))
                        blk.append((v0 << 4) | v1)
            key = bytes(blk)
            if key not in tiles:
                tiles[key] = len(tiles)
            the_map.append(tiles[key])
    if len(tiles) > 255:
        raise ValueError("tile table exceeds u8")
    table = bytearray()
    for blk, _ in sorted(tiles.items(), key=lambda kv: kv[1]):
        table.extend(blk)
    out = bytearray(struct.pack("<H", len(tiles)))
    out.extend(table)
    out.extend(the_map)
    with open(os.path.join(DST, "pitch.bin"), "wb") as fh:
        emit(os.path.join(DST, "pitch.bin"), bytes(out))
    with open(os.path.join(DST, "pitchpal.txt"), "w") as fh:
        fh.write(", ".join(f"({r},{g},{b})" for r, g, b in col) + "\n")
    print("pitch tiles:", len(tiles), "bytes:", len(out))


def main():
    os.makedirs(DST, exist_ok=True)
    if len(sys.argv) > 1 and sys.argv[1] == "sounds":
        convert_sounds()
        return
    if len(sys.argv) > 1 and sys.argv[1] == "pitchart":
        convert_pitch_art(sys.argv[2] if len(sys.argv) > 2 else "nor")
        return
        return
    convert_sheets()
    convert_title()
    convert_pitch_art()
    convert_sounds()
    convert_tactics()


if __name__ == "__main__":
    main()
