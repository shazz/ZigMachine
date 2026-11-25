"""The aurora's ray march: a numpy port of the lab's GLSL `FS_SCENE` (aurora_lab.html), float32 like the GPU.

Same constants, same noise (`h1` is the shader's `fract(sin(n) * 43758.5453)`, `vn`/`fbm` as written there),
same camera, same slab-limited march and the same emission ramp. Deviations (see docs/boot/AURORA_BOOT.md):
the shader's per-pixel jitter hash is kept (`jitter="grain"`) or replaced by the centre of each step
(`jitter="centre"`, grain-free); sin() is numpy's float32, not the GPU's.
"""
import numpy as np

from aurora_common import H, W, smooth

F = np.float32
H1_MIN, H1_N = -4096, 8192


def _h1_table():
    n = np.arange(H1_MIN, H1_MIN + H1_N, dtype=F)
    v = np.sin(n) * F(43758.5453)
    return (v - np.floor(v)).astype(F)


H1 = _h1_table()


def h1(i):
    k = i.astype(np.int64) - H1_MIN
    if k.min() < 0 or k.max() >= H1_N:
        raise ValueError("noise argument outside the tabulated range")
    return H1[k]


def vn(x):
    i = np.floor(x)
    f = x - i
    f = f * f * (F(3) - F(2) * f)
    a, b = h1(i), h1(i + F(1))
    return a * (F(1) - f) + b * f


def fbm(x):
    return F(.5) * vn(x) + F(.25) * vn(x * F(2.03) + F(3.1)) + F(.125) * vn(x * F(4.11) + F(7.7))


def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (F(3) - F(2) * t)


def camera(p):
    """Per-pixel ray directions (H, W, 3), rows top-down; GL's y runs bottom-up."""
    gx = np.arange(W, dtype=F) + F(.5)
    gy = (H - 1 - np.arange(H, dtype=F)) + F(.5)
    ux = (gx[None, :] - F(.5 * W)) / F(H)
    uy = (gy[:, None] - F(.5 * H)) / F(H)
    ux, uy = np.broadcast_arrays(ux, uy)
    d = np.stack([ux * F(p["fov"]), uy * F(p["fov"]), np.ones_like(ux)], -1)
    d /= np.linalg.norm(d, axis=-1, keepdims=True)
    cp, sp = F(np.cos(p["pitch"])), F(np.sin(p["pitch"]))
    dx, dy, dz = d[..., 0], d[..., 1] * cp + d[..., 2] * sp, -d[..., 1] * sp + d[..., 2] * cp
    cy, sy = F(np.cos(p["yaw"])), F(np.sin(p["yaw"]))
    return np.stack([dx * cy + dz * sy, dy, -dx * sy + dz * cy], -1).astype(F)


def sky_mask(p):
    """The photo branch of the shader: `sky = v.y > uHorizon`, v.y bottom-up."""
    vy = ((H - 1 - np.arange(H)) + .5) / H
    return np.broadcast_to((vy > p["horizon"])[:, None], (H, W))


def curtain_z(x, k, t, p):
    s = F(p["dist"]) * (F(1) + F(.38) * k)
    ff = F(p["foldFreq"])
    w = np.sin(x * ff * F(.020) + t * F(p["foldSpeed"]) + k * F(2.1)) * F(.55) \
        + np.sin(x * ff * F(.047) - t * F(p["foldSpeed"]) * F(1.3) + k) * F(.3)
    return s + F(p["foldAmp"]) * (w + F(1.3) * (fbm(x * ff * F(.012) + t * F(p["foldSpeed"]) * F(.25) + k * F(10)) - F(.5)))


def emis(h, p):
    c0, c1, c2 = (np.array(p[k], dtype=F) for k in ("c0", "c1", "c2"))
    c = c0 + (c1 - c0) * smoothstep(F(0), F(p["s0"]), h)[..., None]
    return c + (c2 - c) * smoothstep(F(p["s0"]), F(p["s1"]), h)[..., None]


def _jitter(frag_x, frag_y, time, mode):
    if mode == "centre":
        return np.full(frag_x.shape, F(.5), dtype=F)
    off = F(time * 7) - np.floor(F(time * 7))
    v = np.sin((frag_x + off) * F(127.1) + (frag_y + off) * F(311.7)) * F(43758.5453)
    return (v - np.floor(v)).astype(F)


def _march_curtain(k, d, jit, time, p, acc):
    """Add one curtain's light for the pixels `d` (N, 3) into `acc` (N, 3)."""
    tb0, tb1 = F(p["base"]) / d[:, 1], F(p["base"] + p["height"]) / d[:, 1]
    s = F(p["dist"]) * (F(1) + F(.38) * k)
    m = F(2.2 * p["foldAmp"] + 3 * p["thick"])
    t0, t1 = np.maximum(tb0, (s - m) / d[:, 2]), np.minimum(tb1, (s + m) / d[:, 2])
    live = t0 < t1
    dt = np.where(live, (t1 - t0) / F(p["steps"]), F(0)).astype(F)
    for i in range(int(p["steps"])):
        pt = d * np.where(live, t0 + dt * (F(i) + jit), F(0))[:, None]  # dead pixels stay at the origin
        q = (pt[:, 2] - curtain_z(pt[:, 0], F(k), F(time), p)) / F(p["thick"])
        sheet = np.exp(-q * q)
        h = (pt[:, 1] - F(p["base"])) / F(p["height"])
        prof = smoothstep(F(0), F(p["edge"]), h) * np.exp(-h * F(p["decay"]))
        ray = np.power(fbm(pt[:, 0] * F(p["rayDen"]) * F(.06) + F(time * p["raySpd"]) + F(k * 31)), F(p["rayCon"])) * F(2.2)
        w = np.where(live & (sheet >= F(.02)), sheet * prof * ray * dt, F(0))
        acc += emis(h, p) * w[:, None]


def march(p, ta, rays, sky, jitter="grain"):
    """Raw `acc` (H, W, 3) of the shader at aurora time `ta` (seconds into the aurora)."""
    time = 2.0 + max(0.0, ta)
    ok = sky & (rays[..., 1] > .002) & (rays[..., 2] > .02)
    ys, xs = np.nonzero(ok)
    d = rays[ys, xs]
    jit = _jitter(xs.astype(F) + F(.5), (H - 1 - ys).astype(F) + F(.5), time, jitter)
    acc = np.zeros((len(ys), 3), dtype=F)
    for k in range(int(p["curtains"])):
        _march_curtain(k, d, jit, time, p, acc)
    out = np.zeros((H, W, 3), dtype=F)
    out[ys, xs] = acc
    return out


def envelope(p, ta):
    """The shader's `uEnv`: the aurora's fade in and out."""
    if ta < 0 or ta > p["dur"]:
        return 0.0
    a = min(1.0, ta / p["fadeIn"])
    b = min(1.0, max(0.0, (p["dur"] - ta) / p["fadeOut"]))
    return smooth(a) * smooth(b)
