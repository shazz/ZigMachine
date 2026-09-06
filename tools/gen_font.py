#!/usr/bin/env python3
# Convert an authentic Atari ST system bitmap font (BDF) into the raw byte format
# ZigOS embeds: 256 glyphs, glyph N at offset N*(W*H), row-major WxH, one byte
# per pixel (1=ink, 0=paper), MSB=left column. Cell size W,H and the baseline
# (FONT_ASCENT) are read from the BDF header; glyphs are placed by ENCODING
# (ISO10646; ASCII 32-126 map 1:1 — all the GEM UI uses).
#
# Sources (public domain), from frno7/font:
#   atari/atari-st-system-8x8.bdf  -> zigos/assets/fonts/system_font_atari_1bit.raw
#   atari/atari-st-system-6x6.bdf  -> zigos/assets/fonts/system_font_atari_6x6.raw
# Usage:
#   python3 tools/gen_font.py <in.bdf> <out.raw>
import sys


def header(path):
    w = h = asc = None
    for line in open(path):
        t = line.split()
        if not t:
            continue
        if t[0] == "FONTBOUNDINGBOX":
            w, h = int(t[1]), int(t[2])
        elif t[0] == "FONT_ASCENT":
            asc = int(t[1])
        elif t[0] == "ENDPROPERTIES":
            break
    return w, h, asc


def glyphs(path):
    out = {}
    enc = bbx = bits = None
    reading = False
    for line in open(path):
        t = line.split()
        if not t:
            continue
        if t[0] == "ENCODING":
            enc = int(t[1])
        elif t[0] == "BBX":
            bbx = list(map(int, t[1:5]))
        elif t[0] == "BITMAP":
            bits, reading = [], True
        elif t[0] == "ENDCHAR":
            if enc is not None and 0 <= enc < 256 and bbx is not None:
                out[enc] = (bbx, bits)
            enc = bbx = bits = None
            reading = False
        elif reading:
            bits.append(int(t[0], 16))
    return out


def main():
    src, dst = sys.argv[1], sys.argv[2]
    W, H, ASC = header(src)
    cell = W * H
    out = bytearray(256 * cell)  # zero-filled; blank glyphs stay blank
    for enc, (bbx, rows) in glyphs(src).items():
        bw, bh, bx, by = bbx
        for i, rowval in enumerate(rows):
            cell_row = ASC - by - bh + i
            if not (0 <= cell_row < H):
                continue
            for j in range(bw):
                if (rowval >> (7 - j)) & 1:  # bw<=8: one byte/row, bit 7 = left
                    col = bx + j
                    if 0 <= col < W:
                        out[enc * cell + cell_row * W + col] = 1
    with open(dst, "wb") as f:
        f.write(out)
    print(f"wrote {dst} ({W}x{H}, {len(out)} bytes) from {src}")


if __name__ == "__main__":
    main()
