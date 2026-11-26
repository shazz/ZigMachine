"""Variant G's star plane, baked to the pixel: per 60 Hz frame, the plane-1 bytes that change (overlay.bin).

The other variants ship the 30 fps star records and the cart draws them every frame (seek, midpoint on the odd
frame, clear, a DDA line per falcon edge, a cross per bright star, the name). G draws NOTHING: the baker runs that
same drawing here, integer for integer (the cart's plot.zig and stars.zig), for every 60 Hz frame, and keeps only
the pixels that differ from the frame before. The cart writes them (overlay.zig): "only modify what needs to be
modified". Stars are one pixel each (Matt, 26 Nov: no glint cross). The wire and the name keep their palette
entries (LINE, 128..255): their fade is still the entry's alpha, rewritten by the cart.

overlay.bin: for each 60 Hz frame 0..last, u16 LE count, then count x (u16 LE offset into the 320 x 200 plane, u8 entry).
"""
import numpy as np

W, H = 320, 200
LINE = 16  # look.zig LINE


class OverlayError(ValueError):
    pass


def _put(pl, x, y, c):
    if 0 <= x < W and 0 <= y < H:
        pl[y, x] = c


def _tdiv(a, b):
    """Zig's @divTrunc."""
    q = abs(a) // abs(b)
    return q if (a >= 0) == (b > 0) else -q


def line(pl, x0, y0, x1, y1, c):
    """plot.zig `line`: Q4 endpoints, Q16 steps, one divide a line."""
    dx, dy = x1 - x0, y1 - y0
    n = max(abs(dx), abs(dy)) >> 4
    if n == 0:
        _put(pl, (x0 + 8) >> 4, (y0 + 8) >> 4, c)
        return
    sx, sy = _tdiv(dx << 12, n), _tdiv(dy << 12, n)
    x, y = (x0 << 12) + (1 << 15), (y0 << 12) + (1 << 15)
    for _ in range(n + 1):
        _put(pl, x >> 16, y >> 16, c)
        x += sx
        y += sy


def raster(rec, f, n, nv, edges, word):
    """The star plane (H, W) u8 at 60 Hz frame f: stars.zig's seek + draw (dots only), then the name over them."""
    r = min(f // 2, len(rec) - 1)
    cur = rec[r].astype(np.int64)
    odd = f & 1 == 1 and r + 1 < len(rec)
    nxt = (rec[r + 1].astype(np.int64) - cur) >> 1 if odd else np.zeros_like(cur)  # half the next delta (arith. shift)
    at = cur + nxt
    pl = np.zeros((H, W), np.uint8)
    s = 3 * n + 2 * nv
    if cur[s] > 0:
        for a, b in edges:
            line(pl, at[3 * n + a], at[3 * n + nv + a], at[3 * n + b], at[3 * n + nv + b], LINE)
    for k in range(n):
        lv = int(cur[2 * n + k]) & 15
        if lv:
            _put(pl, int(at[k]), int(at[n + k]), lv)
    if cur[s + 1] > 0 and word is not None:
        x0, y0, img = word
        h, w = img.shape
        sub = pl[y0:y0 + h, x0:x0 + w]
        sub[img != 0] = img[img != 0]
    return pl


def parse_word(blob):
    """word.bin -> (x0, y0, image)."""
    x0, y0, w, h = np.frombuffer(blob[:8], "<u2").astype(int)
    if len(blob) != 8 + w * h or x0 + w > W or y0 + h > H:
        raise OverlayError("word.bin does not match its header or leaves the screen")
    return x0, y0, np.frombuffer(blob[8:], np.uint8).reshape(h, w)


def bake(rec, n, nv, edges, word, last, probes=()):
    """(overlay.bin, {frame: md5-able plane}) for 60 Hz frames 0..last."""
    prev = np.zeros((H, W), np.uint8)
    out, shots = bytearray(), {}
    for f in range(last + 1):
        pl = raster(rec, f, n, nv, edges, word)
        at = np.nonzero((pl != prev).ravel())[0]
        if len(at) > 0xFFFF:
            raise OverlayError(f"frame {f}: {len(at)} changes")
        out += len(at).to_bytes(2, "little")
        rows = np.zeros(len(at), [("o", "<u2"), ("v", "u1")])
        rows["o"], rows["v"] = at, pl.ravel()[at]
        out += rows.tobytes()
        if f in probes:
            shots[f] = pl
        prev = pl
    return bytes(out), shots


def scalars(rec, n, nv):
    """(line, word, fade) per record, the cart's colour levels (u8 each)."""
    s = rec[:, 3 * n + 2 * nv:3 * n + 2 * nv + 3]
    if s.min() < 0 or s.max() > 255:
        raise OverlayError("a scalar leaves 0..255")
    return s.astype(np.uint8)


def meta_source(sc, deltas):
    rows = ", ".join(f".{{ {a}, {b}, {c} }}" for a, b, c in sc.tolist())
    tab = ", ".join(str(int(v)) for v in list(deltas) + [0] * (256 - len(deltas)))  # 256: any escape byte is in range
    return (f"pub const OVERLAY: u32 = 1; // the star plane is baked per 60 Hz frame (overlay.bin, aurora_overlay.py)\n"
            f"pub const SCALARS = [_][3]u8{{ {rows} }}; // per record: wire level, name level, fade\n"
            f"pub const DELTAS = [256]u16{{ {tab} }}; // the aurora's codes (aurora_mask.py), most frequent first\n")
