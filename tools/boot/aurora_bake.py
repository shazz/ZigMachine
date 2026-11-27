#!/usr/bin/env python3
"""Bake the Aurora boot screen's data (cart 161 `aurora_boot`, the board's power-on boot). See docs/boot/AURORA_BOOT.md.

  uv run --with numpy --with pillow python tools/boot/aurora_bake.py [--cache FILE] [--out DIR] [--font FILE]
      [--zx0pack zig-out/bin/zx0pack] [--frames N] [--window --out DIR]
      (--frames: N aurora frames + the closing dark one, for tests; --window: the 320x200 window of G2, the boot
       until 27 Nov, never into the boot's assets: it needs --out)

Writes the whole asset set for the whole 400x280 raster (the boot since variant H) to
apps/zig/assets/screens/aurora_boot/ (aurora_set.py lists the files). Two deviations
from Matt's tuned lab settings are applied here, both his calls: the curtains' Edge sharpness 0.15 (the lab's 0.045
draws their bases as hard steps in the float render itself, 25 Nov), and the name as his script font at 0.42 of the
falcon's wingspan (26 Nov). The font is local only (prototypes/, never committed): only the baked image ships.

Deterministic: the same inputs give the same bytes (no random numbers; float32 libm differences between numpy
builds can move a rare pixel by one level, so the committed assets are the reference, re-baked only on purpose;
the harness reads the reference the baker writes).
"""
import argparse
import json
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import aurora_set as aset  # noqa: E402
import aurora_common as ac  # noqa: E402
from aurora_common import load_settings  # noqa: E402
from aurora_frames import render_frames  # noqa: E402
from aurora_photo import extract, resize_cover  # noqa: E402
from aurora_word import WordError  # noqa: E402

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
ASSETS = ROOT / "apps/zig/assets/screens"
FONT = ROOT / "prototypes/boot_screen/font_christmas_shine/dl/extracted/ChristmasShineFONT.otf"  # local only, never committed (--font)
EDGE = 0.15  # the curtains' Edge sharpness (the lab's slider; 0.045 in Matt's settings draws hard steps)
WORD_SCALE = 0.42  # the name's width, of the falcon's wingspan at the hold


def load_or_render(p, cleaned, cache, frames):
    """(base levels, light). `frames` N (the tests): the first N aurora frames, then the closing dark one (the film
    must end on the clean sky, aurora_direct.build_direct)."""
    if cache and Path(cache).exists():
        z = np.load(cache)
        return z["base"], z["light"]
    base_q, light = render_frames(p, cleaned, "centre", n=frames)
    if frames is not None:
        light = np.concatenate([light, np.zeros_like(light[:1])])
    if cache:
        np.savez(cache, base=base_q, light=light)
    return base_q, light


def bake(settings, photo, out, zx0pack, frames=None, sound=None, cache=None, font=FONT):
    if not Path(font).exists():  # before minutes of rendering: a missing font is an error, never a blank name
        raise WordError(f"wordmark font not found at {font} (local only, see font_christmas_shine/SOURCE.txt; --font)")
    p = dict(load_settings(settings), edge=EDGE)
    stars, cleaned = extract(resize_cover(photo), p["starThr"], band=(p["bandTop"], p["bandBot"]))
    base_q, light = load_or_render(p, cleaned, cache, frames)
    return aset.bake_set(p, stars, (cleaned, base_q, light), out, zx0pack, sound, Path(font), WORD_SCALE)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--settings", default=str(HERE / "aurora_settings.json"))
    ap.add_argument("--photo", default=str(ASSETS / "aurora_boot/stars2.jpg"))
    ap.add_argument("--sound", default=str(ASSETS / "aurora_boot/boot_northern_lights_8s5.wav"))
    ap.add_argument("--out", default=None, help="default: the boot's assets dir, aurora_boot (not with --window)")
    ap.add_argument("--window", action="store_true", help="the 320x200 window (G2) instead of the whole raster")
    ap.add_argument("--zx0pack", default=str(ROOT / "zig-out/bin/zx0pack"))
    ap.add_argument("--frames", type=int, default=None, help="aurora frames to render (default: all)")
    ap.add_argument("--font", default=str(FONT), help="the wordmark's font (local only; a worktree passes the main checkout's)")
    ap.add_argument("--cache", default=None, help="a .npz of the rendered light (edge 0.15): reused if present, else written")
    a = ap.parse_args(argv)
    if a.window and not a.out:  # the cart plays the whole raster: a window set in its assets would break the boot
        ap.error("--window needs --out (the boot's assets are the whole raster's)")
    if not a.window:
        ac.set_screen(*ac.FULL)
    out = a.out or str(ASSETS / "aurora_boot")
    ref = bake(a.settings, a.photo, out, a.zx0pack, a.frames, a.sound, a.cache, a.font)
    print(json.dumps(dict(sizes=ref["sizes"], stats=ref["stats"]), indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
