"""Generated gradient pictures for tools/mpp_convert.py: smooth ramps and NO noise.

A 256-colour palette cannot follow a slow ramp across a whole picture, so these
band visibly in mode 1 while per-line palettes hold them. Deterministic, like
tools/mpp_picture.py (which has +-3 of noise and so packs worse).
"""
import math

from PIL import Image

W, IMAGE_H = 320, 180


def clamp8(v):
    return max(0, min(255, int(round(v * 255))))


def lerp_stops(stops, t):
    """Colour at t in [0, 1] along [(t, (r, g, b)), ...] stops, linearly."""
    for (a, ca), (b, cb) in zip(stops, stops[1:]):
        if a <= t <= b:
            u = (t - a) / (b - a)
            return [ca[k] + (cb[k] - ca[k]) * u for k in range(3)]
    return list(stops[-1][1])


DUSK = [(0.0, (0.02, 0.04, 0.18)), (0.45, (0.30, 0.15, 0.45)), (0.78, (0.95, 0.45, 0.25)), (1.0, (1.0, 0.80, 0.45))]
SUN = (205, 118)


def halo():
    """A dusk sky, deep blue to orange, and a low sun with a wide soft halo."""
    img = Image.new("RGB", (W, IMAGE_H))
    px = img.load()
    for y in range(IMAGE_H):
        base = lerp_stops(DUSK, y / (IMAGE_H - 1))
        for x in range(W):
            d = math.hypot(x - SUN[0], (y - SUN[1]) * 1.1)
            glow = 0.85 * math.exp(-(d / 70) ** 2) + 0.35 * math.exp(-(d / 22) ** 2)
            core = 1.0 if d < 9 else max(0.0, 1 - (d - 9) / 2)
            c = [base[k] + glow * (1.0, 0.75, 0.45)[k] for k in range(3)]
            c = [c[k] * (1 - core) + core * (1.0, 0.97, 0.85)[k] for k in range(3)]
            px[x, y] = tuple(clamp8(min(1.0, v)) for v in c)
    return img


RIDGES = [  # horizon y, amplitude, wavelength seed, fog (0 near .. 1 far)
    (70, 16, 0.9, 0.86), (92, 20, 1.7, 0.66), (116, 22, 2.6, 0.44), (142, 18, 3.4, 0.20),
]
MIST_SKY = [(0.0, (0.46, 0.55, 0.70)), (0.55, (0.86, 0.80, 0.78)), (1.0, (0.98, 0.86, 0.72))]
HILL = (0.10, 0.16, 0.20)


def ridge(x, h0, amp, seed):
    return h0 - amp * (0.6 * math.sin(x * 0.013 * seed + seed) + 0.4 * math.sin(x * 0.031 * seed + 2 * seed))


def hills():
    """Ridges fading into morning fog: each ridge's colour moves only down the rows."""
    img = Image.new("RGB", (W, IMAGE_H))
    px = img.load()
    for x in range(W):
        tops = [ridge(x, h0, amp, seed) for h0, amp, seed, _ in RIDGES]
        for y in range(IMAGE_H):
            # the sun behind the fog, low on the right: a wide warm glow across the columns
            glow = math.exp(-(((x - 250) / 120) ** 2 + ((y - 60) / 90) ** 2))
            sky = [v + glow * w for v, w in zip(lerp_stops(MIST_SKY, y / (IMAGE_H - 1)), (0.30, 0.16, -0.10))]
            sky = [min(1.0, max(0.0, v)) for v in sky]
            c = sky
            for top, (_, _, _, fog) in zip(tops, RIDGES):
                cover = min(1.0, max(0.0, y + 0.5 - top))  # antialiased ridge line
                if cover > 0:  # nearer ridges overwrite; mist thins toward each ridge's foot
                    depth = min(1.0, max(0.0, y - top) / 60)
                    f = fog * (1 - 0.35 * depth)
                    c = [(HILL[k] * (1 - f) + sky[k] * f) * cover + c[k] * (1 - cover) for k in range(3)]
            px[x, y] = tuple(clamp8(v) for v in c)
    return img


BALL = (160, 92, 72)  # cx, cy, radius
KEY = (-0.55, -0.60, 0.58)  # the softbox, up-left of the camera


def backdrop(x, y):
    """A studio sweep: a warm grey pool of light fading to charcoal at the edges."""
    g = math.exp(-(((x - 120) / 190) ** 2 + ((y - 50) / 150) ** 2))
    return [0.06 + 0.52 * g, 0.06 + 0.46 * g, 0.07 + 0.40 * g]


def ball(x, y):
    """A glossy blue ball: soft diffuse, a broad softbox highlight, a rim of fresnel."""
    cx, cy, r = BALL
    dx, dy = (x - cx) / r, (y - cy) / r
    d2 = dx * dx + dy * dy
    if d2 >= 1.0:
        return None
    nz = math.sqrt(1 - d2)
    kn = math.sqrt(sum(v * v for v in KEY))
    lx, ly, lz = (v / kn for v in KEY)
    diff = max(0.0, dx * lx + dy * ly + nz * lz)
    spec = max(0.0, 2 * diff * nz - lz) ** 12  # broad: a softbox, not a point light
    rim = (1 - nz) ** 3
    base = (0.10, 0.28, 0.75)
    return [base[k] * (0.12 + 0.88 * diff) + 0.85 * spec + 0.30 * rim * (0.9, 0.8, 0.7)[k] for k in range(3)]


def studio():
    """The ball on the backdrop, with a soft contact shadow under it."""
    img = Image.new("RGB", (W, IMAGE_H))
    px = img.load()
    cx, cy, r = BALL
    for y in range(IMAGE_H):
        for x in range(W):
            c = ball(x, y)
            if c is None:
                c = backdrop(x, y)
                shade = 1 - 0.55 * math.exp(-(((x - cx - 18) / (r * 1.1)) ** 2 + ((y - cy - r) / 14) ** 2))
                c = [v * shade for v in c]
            px[x, y] = tuple(clamp8(min(1.0, v)) for v in c)
    return img
