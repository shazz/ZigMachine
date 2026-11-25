"""Variant E: a hue-locked halo.

The bloom halo adds only 0 to 3 565 levels over the dark sky, and R / B (5 bits) step at different places than G
(6 bits): with each channel quantised on its own, every contour is a different tint and the halo reads as
colour stains. Here the halo's colour is locked to ONE direction (the mean hue of the faint light), so its
brightness steps are the same tint everywhere; above `T1` levels the true colour takes over, blended between
`T0` and `T1` so there is no seam.
"""
import numpy as np

T0, T1 = 3.0, 7.0  # max channel, in 565 levels
FAINT = (0.5, T1)


def hue(light):
    """The mean direction of the faint light (3,), normalised so its largest component is 1."""
    mx = light.max(-1)
    m = (mx > FAINT[0]) & (mx < FAINT[1])
    if not m.any():
        raise ValueError("no faint light to take a halo hue from")
    c = light[m].mean(0)
    return (c / c.max()).astype(np.float32)


def lock(light):
    """light (n, H, W, 3) float -> the same with the faint part moved onto the hue line."""
    c = hue(light)
    s = (light @ c) / float(c @ c)
    locked = s[..., None] * c
    t = np.clip((light.max(-1) - T0) / (T1 - T0), 0, 1)
    w = (1 - t * t * (3 - 2 * t))[..., None]
    return (w * locked + (1 - w) * light).astype(np.float32)
