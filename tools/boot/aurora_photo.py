"""The sky photo at 320x200 and the star extraction (aurora_lab.html `extractPhoto`).

The canvas's drawImage(cover) is a point-sampled bilinear resize; `resize_cover` reproduces that
(no antialiasing, which is what keeps the stars bright), then `extract` finds the local maxima with a
ring contrast, paints them out and returns them brightest first.
"""
import numpy as np
from PIL import Image

import aurora_common as ac


class PhotoError(ValueError):
    pass


def resize_cover(path):
    """RGB uint8 (H, W, 3): the photo scaled to cover the screen (ac.W x ac.H) and centred (PIL bicubic).

    The lab's canvas drawImage resamples with the browser's own filter; bicubic finds 237 stars against
    the 254 its JSON reports (lanczos 282, bilinear 121, box 455): the closest PIL filter.
    """
    try:
        im = Image.open(path).convert("RGB")
    except OSError as e:
        raise PhotoError(f"cannot read photo {path}: {e}") from e
    pw, ph = im.size
    s = max(ac.W / pw, ac.H / ph)
    sw, sh = min(pw, ac.W / s), min(ph, ac.H / s)  # the side that fits exactly can round a hair past the photo
    box = ((pw - sw) / 2, (ph - sh) / 2, (pw + sw) / 2, (ph + sh) / 2)
    return np.asarray(im.resize((ac.W, ac.H), Image.BICUBIC, box=box)).copy()


def inpaint(img, x, y):
    """Paint the star at (x, y) out of `img` (float, in place): each pixel of its 3x3 gets the average of a
    horizontal and a vertical linear interpolation between the ring samples two pixels away, so a star in a
    gradient leaves the gradient (the lab's flat fill left a rectangle). Reads the CURRENT pixels, as the lab."""
    for j in (-1, 0, 1):
        for i in (-1, 0, 1):
            t_x, t_y = (i + 2) / 4, (j + 2) / 4
            h = img[y + j, x - 2] * (1 - t_x) + img[y + j, x + 2] * t_x
            v = img[y - 2, x + i] * (1 - t_y) + img[y + 2, x + i] * t_y
            img[y + j, x + i] = (h + v) / 2


def extract(rgb, thr, max_stars=800, band=(0.0, 70.0)):
    """(stars, cleaned): stars = [(x, y, b, ph)] brightest first, found only between rows band[0] % and band[1] %
    of the height (the airglow and treeline are not stars); the stars painted out of `cleaned`."""
    lo, hi = ac.H * band[0] / 100, ac.H * band[1] / 100
    d = rgb.astype(np.float64)
    lum = (0.2126 * d[..., 0] + 0.7152 * d[..., 1] + 0.0722 * d[..., 2]) / 255
    found = []
    for y in range(2, ac.H - 2):
        if not lo <= y < hi:
            continue
        for x in range(2, ac.W - 2):
            v = lum[y, x]
            if v < thr or (lum[y - 1:y + 2, x - 1:x + 2] > v).any():
                continue
            ring = (lum[y - 2, x - 2:x + 3].sum() + lum[y + 2, x - 2:x + 3].sum()
                    + lum[y - 1:y + 2, x - 2].sum() + lum[y - 1:y + 2, x + 2].sum()) / 16
            if v - ring >= 0.12:
                found.append((x, y, min(1.0, (v - ring) * 1.6 + 0.2), (x * 7 + y * 13) % 628 / 100))
    found.sort(key=lambda s: -s[2])  # stable, as JS's sort
    stars = found[:max_stars]
    out = d.copy()
    for x, y, _, _ in stars:
        inpaint(out, x, y)
    return stars, np.clip(np.rint(out), 0, 255).astype(np.uint8)
