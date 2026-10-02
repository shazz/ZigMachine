"""tny.py: Tiny Stuff (.TNY) decoder, transcribed from DUNE.PRG's own depacker ($3D6A)."""
import struct


def decode(d: bytes) -> tuple[list[int], bytes]:
    """Return (16 ST palette words, 32000-byte low-res screen)."""
    p = 1 + (4 if d[0] > 2 else 0)
    pal = list(struct.unpack('>16H', d[p:p + 32]))
    nctl, nwords = struct.unpack('>HH', d[p + 32:p + 36])
    ctl = d[p + 36:p + 36 + nctl]
    data = d[p + 36 + nctl:]
    words = [data[i:i + 2] for i in range(0, nwords * 2, 2)]
    scr = bytearray(32000)
    pos = [0]
    wi = 0

    def put(w):
        o = pos[0]
        scr[o:o + 2] = w
        o += 160
        if o >= 32000:
            o -= 31992
            if o >= 160:
                o -= 158
        pos[0] = o

    i = 0
    while i < nctl:
        c = ctl[i]
        if c == 0:
            n = struct.unpack('>H', ctl[i + 1:i + 3])[0]
            i += 3
            rep = True
        elif c == 1:
            n = struct.unpack('>H', ctl[i + 1:i + 3])[0]
            i += 3
            rep = False
        else:
            n = c - 256 if c > 127 else c
            i += 1
            rep = n > 0
            n = abs(n)
        if rep:
            for _ in range(n):
                put(words[wi])
            wi += 1
        else:
            for _ in range(n):
                put(words[wi])
                wi += 1
    return pal, bytes(scr)


def to_rgb(pal: list[int], scr: bytes):
    """Planar low-res -> list of 200 rows of 320 palette indices."""
    rows = []
    for y in range(200):
        row = []
        for g in range(20):
            o = y * 160 + g * 8
            pw = struct.unpack('>4H', scr[o:o + 8])
            for b in range(15, -1, -1):
                row.append(sum(((pw[k] >> b) & 1) << k for k in range(4)))
        rows.append(row)
    return rows


def st_rgb(w: int) -> tuple[int, int, int]:
    return tuple(((w >> s) & 7) * 255 // 7 for s in (8, 4, 0))
