"""The lab's post chain (`FS_BLUR`, `FS_OUT`): 1/4-resolution bloom, ACES, gamma, RGB565 (no dither).

The picture the lab shows is tonemap(photo + aurora + bloom of both), so adding a tone-mapped aurora to a
tone-mapped photo would be wrong. The baker therefore renders the whole picture twice, with and without the
aurora, and keeps the difference in RGB565 levels (`diff_levels`): base565 + diff = the lab's picture.
"""
import numpy as np

from aurora_common import H, W

F = np.float32
TAPS = (.227, .195, .122, .054, .016)
LEVELS = np.array([31, 63, 31], dtype=F)


def bilinear(img, u, v):
    """Texture-style LINEAR sample of img (h, w, 3) at texel coordinates (u, v), clamped to the edge."""
    h, w = img.shape[:2]
    u, v = np.clip(u, 0, w - 1), np.clip(v, 0, h - 1)
    x0, y0 = np.floor(u).astype(int), np.floor(v).astype(int)
    x1, y1 = np.minimum(x0 + 1, w - 1), np.minimum(y0 + 1, h - 1)
    fx, fy = (u - x0)[..., None].astype(F), (v - y0)[..., None].astype(F)
    top = img[y0, x0] * (1 - fx) + img[y0, x1] * fx
    bot = img[y1, x0] * (1 - fx) + img[y1, x1] * fx
    return top * (1 - fy) + bot * fy


def blur(scene):
    """The lab's glow: two passes into an (H/4, W/4) target, 5 taps each, sampled with bilinear filtering."""
    bh, bw = H // 4, W // 4
    jj, rr = np.meshgrid(np.arange(bw), np.arange(bh))
    u0, v0 = (jj + .5) * (W / bw) - .5, (rr + .5) * (H / bh) - .5
    a = scene * 0 + 0
    pass1 = TAPS[0] * bilinear(scene, u0, v0)
    for i in range(1, 5):
        off = i * 1.5 * (4 / W) * W  # uDir * i * 1.5 in uv, in scene texels
        pass1 = pass1 + TAPS[i] * (bilinear(scene, u0 + off, v0) + bilinear(scene, u0 - off, v0))
    del a
    ju, jv = jj.astype(float), rr.astype(float)
    out = TAPS[0] * pass1
    for i in range(1, 5):
        off = i * 1.5
        out = out + TAPS[i] * (bilinear(pass1, ju, jv + off) + bilinear(pass1, ju, jv - off))
    return out.astype(F)


def upsample(glow):
    xs, ys = np.meshgrid(np.arange(W), np.arange(H))
    return bilinear(glow, (xs + .5) / 4 - .5, (ys + .5) / 4 - .5)


def aces(x):
    return np.clip((x * (F(2.51) * x + F(.03))) / (x * (F(2.43) * x + F(.59)) + F(.14)), 0, 1)


def picture_f(scene, p):
    """FS_OUT before the quantiser: scene (already x.25) + glow, ACES, gamma, in float 565 levels (H, W, 3)."""
    c = scene * 4 + upsample(blur(scene)) * 4 * F(p["bloom"])
    return np.power(aces(c * F(p["exposure"])), F(1 / 2.2)) * LEVELS


def picture(scene, p):
    """FS_OUT: the lab's picture quantised to RGB565 integer levels (H, W, 3), no dither."""
    return np.floor(picture_f(scene, p) + F(.5)).astype(np.int16)


def diff_levels(base_scene, acc, env, p):
    """(base 565 levels, the aurora's light in FLOAT 565 levels): with - without, >= 0 per channel (ACES is monotone)."""
    lit = base_scene + acc * F(p["gain"] * env * .045 * .25)
    base_f = picture_f(base_scene, p)
    # The aurora's own light in float levels, THEN rounded: rounding (with) - (without) separately would let the
    # photo's grain decide where each channel steps, which reads as per-pixel speckle; this gives clean contours.
    d = picture_f(lit, p) - base_f
    if d.min() < -1e-4:
        raise ValueError("aurora made a channel darker: the add-in-565 playback would be wrong")
    return np.floor(base_f + F(.5)).astype(np.int16), np.maximum(d, 0).astype(F)


def key565(d):
    """A level difference (r5, g6, b5) packed as r | g << 5 | b << 11 (16 bits)."""
    d = d.astype(np.uint16)
    return d[..., 0] | (d[..., 1] << 5) | (d[..., 2] << 11)
