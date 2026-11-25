"""Stage 2 of the baker: the live star plane, played out per 30 fps frame (aurora_lab.html `drawStarPlane`).

Every frame stores, already computed: the (x, y) pixel and brightness level of every star (flight along its
Bezier path with the swirl, delays and the falcon's moving targets applied), the falcon's projected vertices
(Q4 pixels) and three scalars (line level, wordmark level, global fade coefficient). The cart plays points
and lines back; it does no 3D and no float.
"""
import math

import numpy as np

from aurora_common import FPS, beats, smooth
from aurora_falcon import EDGES, NAMES, assign, dot_xy, projected

LEVELS = 15  # star / line / word alpha steps (palette entries 1..15 of each ramp)
GLINT_B = 0.85
Q4 = 16


def _alpha(b, p):
    return min(1.0, (p["starMin"] + (1 - p["starMin"]) * b) * min(1.0, p["starGain"]))


def star_state(s, t, p, b, tgt, dot, delay):
    """(x, y, level 0..15, glint) of star `s` at time t; tgt = this frame's projected dot position or None."""
    x, y, bb, ph = s
    br = min(1.0, bb * p["starGain"]) * (0.82 + 0.18 * math.sin(t * 3 + ph))
    if t > b.m0:
        fly = p["morphLen"] * 0.65
        pr = smooth(min(1, max(0, (t - b.m0 - delay * p["morphLen"]) / fly)))
        tx, ty = tgt
        mx, my = (x + tx) / 2, (y + ty) / 2
        cx, cy = mx + -(ty - y) * p["swirl"] * 0.5, my + (tx - x) * p["swirl"] * 0.5
        q = 1 - pr
        x, y = q * q * x + 2 * q * pr * cx + pr * pr * tx, q * q * y + 2 * q * pr * cy + pr * pr * ty
        br = br + (1 - br) * pr
    return math.floor(x + .5), math.floor(y + .5), round(_alpha(br, p) * LEVELS), br > GLINT_B


def frame_state(i, stars, dots, dot_of, delay, p):
    """One frame: dict of numpy arrays and scalars."""
    b, t = beats(p), i / FPS
    proj = projected(t, p, b)
    sx, sy, lv = [], [], []
    for k, s in enumerate(stars):
        tgt = dot_xy(dots[dot_of[k]], proj) if t > b.m0 else None
        x, y, level, glint = star_state(s, t, p, b, tgt, dot_of[k], delay[k])
        sx.append(x); sy.append(y); lv.append(level | (16 if glint else 0))
    edges_a = min(1.0, max(0.0, (t - b.m1) / (b.e1 - b.m1)))
    word = min(1.0, (t - b.w0) / 0.6) if t > b.w0 else 0.0
    fade = max(0.0, 1 - (t - b.end) / 0.6) if t > b.end else 1.0
    fade_in = max(0.0, 1 - t / p["fadeInSky"]) if p["fadeInSky"] > 0 else 0.0  # from black at t = 0
    return dict(sx=sx, sy=sy, lv=lv, vx=np.rint(proj[:, 0] * Q4).astype(int), vy=np.rint(proj[:, 1] * Q4).astype(int),
                line=round(0.5 * edges_a * LEVELS * 2), word=round(word * LEVELS),
                fade=round(31 * max(1 - fade, fade_in)))


def bake_stars(stars, p):
    """(frames, meta): per 30 fps frame the state, for t = 0 .. total."""
    b = beats(p)
    dots, dot_of, delay = assign(stars, p)
    n = int(math.ceil(b.total * FPS)) + 1
    return [frame_state(i, stars, dots, dot_of, delay, p) for i in range(n)], dict(n=n, edges=EDGES, names=NAMES)
