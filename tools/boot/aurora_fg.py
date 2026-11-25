"""Variants F and G of the aurora: two ways past the ONE shared 256-entry palette of B..E.

F (`rowpal`): a 256-entry palette PER ROW of the band. The aurora's colour follows altitude (violet base, green
  body, violet top), so one row holds a few hundred distinct colours where the whole film holds ~2,300; 256 per
  row then sit within a fraction of a 565 level of the float light (measured in docs/boot/AURORA_BOOT.md). The
  frame data stays one 8-bit index a pixel (delta + ZX0, as E); the cart reads `table[row][index]`.
  A straight per-row hue RAMP (8-bit intensity along one direction) was measured first and is WORSE than E: a
  row mixes curtains at different heights and the bloom halo, so one hue line per row is too few dimensions.
G (`direct`): no palette at all. The final picture (sky + aurora in float, the lab's compositing) rounded to
  RGB565 once, stored as the 16-bit per-pixel difference from the previous frame (wrapping), ZX0 in TWO
  containers a frame (the band's top and bottom halves, offsets 2n + 1); the cart adds it to the plane. The quantiser floor: what any 565 display of the lab can show without dithering.
Neither dithers.
"""
import numpy as np

import aurora_pack as pk
import aurora_palette as pm


def lit_rows(mask):
    """(r0, r1): the rows of `mask` (n, H, W) that are ever true."""
    rows = np.nonzero(mask.any(0).any(1))[0]
    if len(rows) == 0:
        raise pk.PackError("no aurora pixels in any frame")
    return int(rows.min()), int(rows.max()) + 1


def row_palettes(light, base_q, r0, r1):
    """(idx (n, rows, W) u8, pals (rows, 256, 3) i16, headroom fixes): one palette per band row, nearest on the float light."""
    n, _, w, _ = light.shape
    idx = np.zeros((n, r1 - r0, w), np.uint8)
    pals = np.zeros((r1 - r0, 256, 3), np.int16)
    fixes = 0
    mx = np.array([31, 63, 31])
    for k, y in enumerate(range(r0, r1)):
        ly = light[:, y:y + 1]
        if ly.max() < 0.5:  # nothing in this row rounds to light: index 0 everywhere
            continue
        pts, counts = pm.histogram(ly)
        pal = pm.build(pts, counts, 256, 0.5)
        pals[k, :len(pal)] = pal
        q = pm.quantise(ly, pal)
        fixes += pk.fit_headroom(q, pal, (mx - base_q[y:y + 1]))
        idx[:, k] = q[:, 0]
    return idx, pals, fixes


def row_error(light, idx, pals, r0):
    """(mean, max) absolute error in 565 levels per channel against the float light, over the band."""
    rows = np.arange(idx.shape[1])[None, :, None]
    e = np.abs(light[:, r0:r0 + idx.shape[1]] - pals[rows, idx]).reshape(-1, 3)
    return e.mean(0), e.max(0)


def words(levels):
    """565 levels (..., 3) -> pixel words r << 11 | g << 5 | b, u16."""
    p = levels.astype(np.uint32)
    return ((p[..., 0] << 11) | (p[..., 1] << 5) | p[..., 2]).astype(np.uint16)


def direct_frames(light, base_f):
    """(n, H, W, 3) int levels: the final picture of every frame, rounded once (clamped to the channel range)."""
    mx = np.array([31, 63, 31], np.float32)
    return np.clip(np.floor(base_f[None] + light + np.float32(.5)), 0, mx).astype(np.int16)


def direct_deltas(final_w, base_w):
    """u16 (n, rows, W): frame t minus frame t-1 (frame -1 = the sky), wrapping."""
    d = final_w.astype(np.uint16).copy()
    d[0] = final_w[0] - base_w
    d[1:] = final_w[1:] - final_w[:-1]
    return d


def probe_frames(n):
    return sorted({0, n // 4, n // 2, 3 * n // 4, n - 1})


def build_rowpal(light, base_q, zx0pack, work):
    """Variant F: (aurora dict for the baker) per-row palettes, 8-bit index deltas, every row."""
    r0, r1 = lit_rows(light.max(-1) >= 0.5)
    idx, pals, fixes = row_palettes(light, base_q, r0, r1)
    blob, offs = pk.pack_frames(pk.deltas(idx), zx0pack, work)
    table = words(pals)  # (rows, 256) u16
    err = row_error(light, idx, pals, r0)
    sky = words(base_q)
    rows = np.arange(r1 - r0)[:, None]
    planes = {}
    for j in probe_frames(len(idx)):
        p = sky.copy()
        p[r0:r1] = sky[r0:r1] + table[rows, idx[j]]  # headroom proven: a plain add
        planes[j] = p
    return dict(n=len(idx), r0=r0, rows=r1 - r0, blob=blob, offs=offs, files={"palette.bin": table.astype("<u2").tobytes()},
                planes=planes, sky=sky, mode=1, stats=dict(headroom_fixes=fixes, err_mean=err[0].round(3).tolist(), err_max=err[1].round(2).tolist()))


def build_direct(light, base_f, base_q, zx0pack, work):
    """Variant G: the final 565 picture per frame, 16-bit wrapping deltas, every row of the band."""
    final = direct_frames(light, base_f)
    sky = words(base_q)
    fw = words(final)
    r0, r1 = lit_rows(fw != sky[None])
    d = direct_deltas(fw[:, r0:r1], sky[r0:r1])
    mid = (r1 - r0) // 2  # the cart's timeline.splitRow: each half its own container, unpacked on its own 60 Hz frame
    halves = [h for i in range(len(d)) for h in (d[i, :mid], d[i, mid:])]  # (a half-size buffer: G's RAM is tight)
    parts = [pk.zx0(h.astype("<u2").tobytes(), zx0pack, work) for h in halves]
    offs = np.cumsum([0] + [len(x) for x in parts]).astype("<u4").tobytes()
    if (fw[-1] != sky).any():
        raise pk.PackError("the last frame is not the sky: the aurora must end on the clean picture")
    e = np.abs(final - (base_f[None] + light)).reshape(-1, 3)
    return dict(n=len(fw), r0=r0, rows=r1 - r0, blob=b"".join(parts), offs=offs, files={}, planes={j: fw[j] for j in probe_frames(len(fw))},
                sky=sky, mode=2, stats=dict(err_mean=e.mean(0).round(3).tolist(), err_max=e.max(0).round(2).tolist()))
