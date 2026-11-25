"""Stage 1 of the baker: the aurora window rendered to RGB565 level differences.

Output: `base` (H, W, 3) int16 565 levels of the sky without aurora (the picture the cart starts from) and
`keys` (n, H, W) uint16, each frame's per-pixel difference packed by `key565`. Frame i is the aurora at
ta = i / FPS seconds; the cart shows it at 60 Hz / 2.
"""
import numpy as np

from aurora_common import FPS, H, W
from aurora_march import camera, envelope, march, sky_mask
from aurora_post import diff_levels, key565, picture


def base_scene(cleaned_rgb, p):
    """The lab's `col*.25` of the cleaned photo (stars painted out), float32 (H, W, 3)."""
    return ((cleaned_rgb / 255.0) ** 2.2 * p["photoDim"] * .25).astype(np.float32)


def render_frames(p, cleaned_rgb, jitter="grain", n=None, progress=None):
    """(base_levels, keys): n frames (default dur * FPS + 1) of the aurora."""
    n = int(round(p["dur"] * FPS)) + 1 if n is None else n  # + the last, env = 0 frame: the aurora is gone
    scene = base_scene(cleaned_rgb, p)
    rays, sky = camera(p), sky_mask(p)
    keys = np.zeros((n, H, W), dtype=np.uint16)
    for i in range(n):
        ta = i / FPS
        acc = march(p, ta, rays, sky, jitter)
        _, d = diff_levels(scene, acc, envelope(p, ta), p)
        keys[i] = key565(d)
        if progress:
            progress(i, n)
    return picture(scene, p), keys
