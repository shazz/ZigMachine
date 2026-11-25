"""The wordmark of variants F / G: "Kestrel" in Matt's script font, baked to an anti-aliased coverage image.

The font (Christmas Shine by Fandi, free for commercial use; prototypes/boot_screen/font_christmas_shine/SOURCE.txt)
stays local and is never committed: only the baked image ships (`word.bin`). The word is drawn 4x larger and
box-filtered down to the cart's pixels, so each pixel holds its real coverage; no dithering, no 1-bit edge.
The cart shows it on the star plane as palette entries WORD_BASE..255 = the ink at alpha `coverage`, so
FRESCO blends it over the true-colour sky (docs/boot/AURORA_BOOT.md).

word.bin: u16 LE x0, y0, w, h, then w * h bytes, each 0 (no coverage) or WORD_BASE + coverage >> 1.
"""
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

TEXT = "Kestrel"
WORD_BASE = 128  # the first star-plane palette entry of the word (128 alpha steps up to 255)
SS = 4  # supersampling


class WordError(RuntimeError):
    pass


def coverage(font_path, width, text=TEXT):
    """(h, w) float 0..1 coverage of `text`, its ink `width` pixels wide (cropped to its box)."""
    if not Path(font_path).exists():
        raise WordError(f"wordmark font not found at {font_path} (local only, see font_christmas_shine/SOURCE.txt)")
    size = 40 * SS
    for _ in range(2):  # measure, then scale the size so the ink is `width` wide
        font = ImageFont.truetype(str(font_path), size)
        x0, y0, x1, y1 = ImageDraw.Draw(Image.new("L", (1, 1))).textbbox((0, 0), text, font=font)
        size = max(8, int(round(size * width * SS / (x1 - x0))))
    font = ImageFont.truetype(str(font_path), size)
    x0, y0, x1, y1 = ImageDraw.Draw(Image.new("L", (1, 1))).textbbox((0, 0), text, font=font)
    w, h = -(-(x1 - x0 + 2 * SS) // SS) * SS, -(-(y1 - y0 + 2 * SS) // SS) * SS
    im = Image.new("L", (w, h))
    ImageDraw.Draw(im).text((SS - x0, SS - y0), text, font=font, fill=255)
    a = np.asarray(im, np.float32) / 255
    return a.reshape(h // SS, SS, w // SS, SS).mean((1, 3))


def bake(font_path, width, cx, cy, screen=(320, 200)):
    """(word.bin bytes, x0, y0, w, h): the coverage image centred on (cx, cy), clipped to the screen."""
    cov = coverage(font_path, width)
    h, w = cov.shape
    x0, y0 = int(round(cx - w / 2)), min(int(round(cy - h / 2)), screen[1] - 4 - h)  # a tall script stays on screen
    if x0 < 0 or y0 < 0 or x0 + w > screen[0] or y0 + h > screen[1]:
        raise WordError(f"wordmark {w}x{h} at ({x0}, {y0}) leaves the screen")
    c8 = np.rint(cov * 255).astype(np.int32)
    idx = np.where(c8 >= 2, WORD_BASE + (c8 >> 1), 0).astype(np.uint8)
    head = np.array([x0, y0, w, h], "<u2").tobytes()
    return head + idx.tobytes(), x0, y0, w, h
