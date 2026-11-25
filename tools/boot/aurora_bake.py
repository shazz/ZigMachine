#!/usr/bin/env python3
"""Bake the Aurora boot screen's data (cart 161 `aurora_boot`). See docs/boot/AURORA_BOOT.md.

  uv run --with numpy --with pillow python tools/boot/aurora_bake.py \\
      [--out apps/zig/assets/screens/aurora_boot] [--zx0pack zig-out/bin/zx0pack] [--frames N] [--jitter grain|centre]

Deterministic: the same inputs give the same bytes (no random numbers; float32 libm differences between
numpy builds can move a rare pixel by one level, so the committed assets are the reference, re-baked only
on purpose, and the harness pins are re-taken with them).
"""
import argparse
import json
import sys
import tempfile
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import aurora_emit as em  # noqa: E402
import aurora_pack as pk  # noqa: E402
import aurora_sound as snd  # noqa: E402
import aurora_palette as pm  # noqa: E402
from aurora_common import FPS, beats, load_settings  # noqa: E402
from aurora_frames import render_frames  # noqa: E402
from aurora_photo import extract, resize_cover  # noqa: E402
from aurora_stars import bake_stars  # noqa: E402

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent


def star_rows(frames):
    """(records, n_stars, nv): one i16 row per 30 fps frame, the layout of aurora_meta.REC."""
    rows = [f["sx"] + f["sy"] + f["lv"] + list(f["vx"]) + list(f["vy"]) + [f["line"], f["word"], f["fade"]] for f in frames]
    return np.array(rows, dtype=np.int16), len(frames[0]["sx"]), len(frames[0]["vx"])


def build_aurora(keys, base_q, zx0pack, work):
    """(idx_stored, palette, r0, r1, blob, offsets, stats) from the rendered difference keys."""
    uniq, counts = pm.histogram(keys)
    pal = pm.build(uniq, counts, 256, 0.5)
    idx = pm.quantise(keys, uniq, pal)
    r0, r1 = pk.band_rows(keys)
    stored = pk.stored_rows(idx, r0, r1).copy()
    fixed = pk.fit_headroom(stored, pal, pk.headroom(base_q, r0, r1))
    held = pk.hysteresis(stored, pal)
    blob, offs = pk.pack_frames(pk.deltas(held), zx0pack, work)
    return held, pal, r0, r1, blob, offs, dict(unique_keys=len(uniq), headroom_fixes=fixed)


def bake(settings, photo, out, zx0pack, frames=None, jitter="grain", sound=None):
    p = load_settings(settings)
    stars, cleaned = extract(resize_cover(photo), p["starThr"])
    base_q, keys = render_frames(p, cleaned, jitter, n=frames)
    with tempfile.TemporaryDirectory() as work:
        held, pal, r0, r1, blob, offs, stats = build_aurora(keys, base_q, zx0pack, work)
        sky = pk.zx0(((base_q[..., 0].astype("<u2") << 11) | (base_q[..., 1].astype("<u2") << 5) | base_q[..., 2].astype("<u2")).tobytes(), zx0pack, work, "sky.bin")
        star_frames, _ = bake_stars(stars, p)
        rec, n_stars, nv = star_rows(star_frames)
        d = rec.copy()
        d[1:] = rec[1:] - rec[:-1]
        stars_blob = pk.zx0(d.astype("<i2").tobytes(), zx0pack, work, "stars.bin")
    from aurora_falcon import EDGES
    pcm, rate = snd.convert(sound, (len(rec) - 1) / FPS)
    words = pk.pixel_palette(pal)
    sizes = dict(sky=len(sky), aurora=len(blob) + len(offs), stars=len(stars_blob), sound=len(pcm))
    meta = dict(n_stars=n_stars, nv=nv, rec=rec.shape[1], star_frames=len(rec), aurora_frames=len(held), band_y0=r0,
                band_rows=held.shape[1], edges=EDGES, palette=words, sample_rate=rate, sample_len=len(pcm), aurora_at=int(round(beats(p).a0 * FPS)), sizes=sizes)
    n = len(held)
    probes = dict(aurora=sorted({0, n // 4, n // 2, 3 * n // 4, n - 1}), stars=sorted({0, 40, 100, 160, 200} & set(range(len(rec)))))
    ref = em.reference(base_q, words, held, r0, rec, meta, probes)
    ref["stats"] = stats | dict(stars=n_stars, palette=len(pal), band=[r0, r1])
    em.write_assets(out, sky, blob, offs, stars_blob, meta, pcm.tobytes())
    ref['pcm_md5'] = em.md5(pcm)
    (Path(out) / "aurora_ref.json").write_text(json.dumps(ref, indent=1, sort_keys=True))
    return ref


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--settings", default=str(HERE / "aurora_settings.json"))
    ap.add_argument("--photo", default=str(ROOT / "apps/zig/assets/screens/aurora_boot/stars2.jpg"))
    ap.add_argument("--out", default=str(ROOT / "apps/zig/assets/screens/aurora_boot"))
    ap.add_argument("--sound", default=str(ROOT / "apps/zig/assets/screens/aurora_boot/boot_northern_lights_8s5.wav"))
    ap.add_argument("--zx0pack", default=str(ROOT / "zig-out/bin/zx0pack"))
    ap.add_argument("--frames", type=int, default=None, help="aurora frames to render (default: all)")
    ap.add_argument("--jitter", choices=("grain", "centre"), default="grain")
    a = ap.parse_args(argv)
    ref = bake(a.settings, a.photo, a.out, a.zx0pack, a.frames, a.jitter, a.sound)
    print(json.dumps(dict(sizes=ref["sizes"], stats=ref["stats"]), indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
