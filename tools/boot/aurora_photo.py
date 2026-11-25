"""The sky photo at 320x200 and the star extraction (aurora_lab.html `extractPhoto`).

The canvas's drawImage(cover) is a point-sampled bilinear resize; `resize_cover` reproduces that
(no antialiasing, which is what keeps the stars bright), then `extract` finds the local maxima with a
ring contrast, paints them out and returns them brightest first.
"""
import numpy as np
from PIL import Image

from aurora_common import H, W


class PhotoError(ValueError):
    pass


def resize_cover(path):
    """RGB uint8 (H, W, 3): the photo scaled to cover 320x200 and centred (PIL bicubic).

    The lab's canvas drawImage resamples with the browser's own filter; bicubic finds 237 stars against
    the 254 its JSON reports (lanczos 282, bilinear 121, box 455): the closest PIL filter.
    """
    try:
        im = Image.open(path).convert("RGB")
    except OSError as e:
        raise PhotoError(f"cannot read photo {path}: {e}") from e
    pw, ph = im.size
    s = max(W / pw, H / ph)
    sw, sh = W / s, H / s
    box = ((pw - sw) / 2, (ph - sh) / 2, (pw + sw) / 2, (ph + sh) / 2)
    return np.asarray(im.resize((W, H), Image.BICUBIC, box=box)).copy()


def extract(rgb, thr, max_stars=800):
    """(stars, cleaned): stars = [(x, y, b, ph)] brightest first; the stars painted out of `cleaned`."""
    d = rgb.astype(np.float64)
    lum = (0.2126 * d[..., 0] + 0.7152 * d[..., 1] + 0.0722 * d[..., 2]) / 255
    found = []
    for y in range(2, H - 2):
        for x in range(2, W - 2):
            v = lum[y, x]
            if v < thr or (lum[y - 1:y + 2, x - 1:x + 2] > v).any():
                continue
            ring = (lum[y - 2, x - 2:x + 3].sum() + lum[y + 2, x - 2:x + 3].sum()
                    + lum[y - 1:y + 2, x - 2].sum() + lum[y - 1:y + 2, x + 2].sum()) / 16
            if v - ring >= 0.12:
                found.append((x, y, min(1.0, (v - ring) * 1.6 + 0.2), (x * 7 + y * 13) % 628 / 100))
    found.sort(key=lambda s: -s[2])  # stable, as JS's sort
    stars = found[:max_stars]
    out = rgb.copy().astype(np.float64)
    for x, y, _, _ in stars:
        mean = np.concatenate([out[y - 2, x - 2:x + 3], out[y + 2, x - 2:x + 3]]).mean(axis=0)
        out[y - 1:y + 2, x - 1:x + 2] = np.rint(mean)  # canvas rounds half to even
    return stars, out.astype(np.uint8)
