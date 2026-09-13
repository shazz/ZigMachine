"""The procedural truecolor picture tools/mpp_convert.py converts by default.

No photo: the repo is public. Smooth gradients band visibly at 256 colours: a sky
gradient, three Phong-shaded spheres, an HSV-ramp floor, and +-3 of seeded noise
per channel (about 39,000 distinct colours at 320x180). Deterministic.
"""
import math
import random

from PIL import Image

W, IMAGE_H = 320, 180
SPHERES = [  # cx, cy, radius, base colour
    (70, 70, 46, (0.95, 0.30, 0.25)),
    (165, 105, 58, (0.25, 0.80, 0.45)),
    (262, 62, 40, (0.35, 0.45, 1.00)),
]
LIGHT = (-0.45, -0.55, 0.70)
FLOOR_Y = 140


def hsv(h, s, v):
    i = int(h * 6) % 6
    f = h * 6 - int(h * 6)
    p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
    return [(v, t, p), (q, v, p), (p, v, t), (p, q, v), (t, p, v), (v, p, q)][i]


def sky(x, y):
    t = y / (IMAGE_H - 1)
    top, bottom = (0.05, 0.10, 0.35), (0.95, 0.55, 0.35)
    warm = 0.12 * math.sin(x / W * math.pi)
    return tuple(top[k] * (1 - t) + bottom[k] * t + (warm if k == 0 else 0) for k in range(3))


def ground(x, y):
    # hue across, value down, a gentle wave in the hue
    return hsv((x / W + 0.02 * math.sin(y * 0.3)) % 1.0, 0.85, 0.35 + 0.6 * (y - FLOOR_Y) / (IMAGE_H - FLOOR_Y - 1))


def sphere(x, y):
    ln = math.sqrt(sum(c * c for c in LIGHT))
    lx, ly, lz = (c / ln for c in LIGHT)
    for cx, cy, r, base in SPHERES:
        dx, dy = (x - cx) / r, (y - cy) / r
        d2 = dx * dx + dy * dy
        if d2 >= 1.0:
            continue
        nz = math.sqrt(1 - d2)
        diff = max(0.0, dx * lx + dy * ly + nz * lz)
        spec = max(0.0, 2 * diff * nz - lz) ** 24  # reflection toward the viewer
        return tuple(min(1.0, 0.08 + base[k] * (0.15 + 0.85 * diff) + 0.9 * spec) for k in range(3))
    return None


def generate():
    rng = random.Random(1234)
    img = Image.new("RGB", (W, IMAGE_H))
    px = img.load()
    for y in range(IMAGE_H):
        for x in range(W):
            c = sphere(x, y)
            if c is None:
                c = ground(x, y) if y >= FLOOR_Y else sky(x, y)
            px[x, y] = tuple(max(0, min(255, int(c[k] * 255 + rng.uniform(-3, 3)))) for k in range(3))
    return img
