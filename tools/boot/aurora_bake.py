#!/usr/bin/env python3
"""Bake the Aurora boot screen's data (cart 161 `aurora_boot` and its variants). See docs/boot/AURORA_BOOT.md.

  uv run --with numpy --with pillow python tools/boot/aurora_bake.py [--variant main|b|c|d|e] [--cache FILE]
      [--out DIR] [--zx0pack zig-out/bin/zx0pack] [--frames N]

`main` writes the whole asset set to apps/zig/assets/screens/aurora_boot/ (the committed cart 161 is the first bake,
variant A, kept as shipped); a variant (b..e) writes its aurora, sky and star records to
apps/zig/assets/screens/aurora_boot_<v>/ and shares the sound (boot.raw) with `main`.
  b  smooth (no ray-march jitter) light quantised on its float value, 2-level temporal hold, every other row
  c  as b, no temporal hold
  d  as c, every row
  e  as d, the faint halo's hue locked to one direction (aurora_halo.py)
  f  a 256-entry palette PER ROW (aurora_fg.py), every row, no hold, the soft curtain base (edge 0.15), the wordmark a baked image
  g  no palette: the final 565 picture as 16-bit deltas (aurora_fg.py), every row, edge 0.15, the wordmark a baked image
(The committed cart 161 is variant A: the first bake, jittered, integer-difference palette; see the docs.)

Deterministic: the same inputs give the same bytes (no random numbers; float32 libm differences between numpy
builds can move a rare pixel by one level, so the committed assets are the reference, re-baked only on
purpose; the harness reads the reference the baker writes).
"""
import argparse
import json
import sys
import tempfile
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import aurora_emit as em  # noqa: E402
import aurora_fg as fg  # noqa: E402
import aurora_halo as halo  # noqa: E402
import aurora_word as word  # noqa: E402
import aurora_pack as pk  # noqa: E402
import aurora_palette as pm  # noqa: E402
import aurora_sound as snd  # noqa: E402
from aurora_common import FPS, beats, load_settings  # noqa: E402
from aurora_falcon import EDGES  # noqa: E402
from aurora_frames import base_scene, render_frames  # noqa: E402
from aurora_post import picture_f  # noqa: E402
from aurora_photo import extract, resize_cover  # noqa: E402
from aurora_stars import bake_stars  # noqa: E402

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent.parent
ASSETS = ROOT / "apps/zig/assets/screens"
FONT = ROOT / "prototypes/boot_screen/font_christmas_shine/dl/extracted/ChristmasShineFONT.otf"  # local only, never committed
if not FONT.exists():  # a worktree has no prototypes/: the main checkout's copy
    FONT = Path("/home/matt/projects/ZigMachine/prototypes/boot_screen/font_christmas_shine/dl/extracted/ChristmasShineFONT.otf")
VARIANTS = {"main": dict(hold=pk.HYST, step=2), "b": dict(hold=pk.HYST, step=2), "c": dict(hold=0, step=2), "d": dict(hold=0, step=1),
            "e": dict(hold=0, step=1, halo=True),
            # F, G: the lab's Edge sharpness 0.045 draws the curtains' bases as hard steps (in the float render itself,
            # not a quantiser artefact: docs/boot/AURORA_BOOT.md); 0.15 is the soft base. The name is a baked script image
            # (aurora_word.py, Matt's font, 25 Nov), not the bitmap capitals.
            "f": dict(hold=0, step=1, mode="rowpal", edge=0.15, wordmark=2),
            "g": dict(hold=0, step=1, mode="direct", edge=0.15, wordmark=2)}


def star_rows(frames):
    """(records, nv): one i16 row per 30 fps frame, the layout of aurora_meta.REC."""
    rows = [f["sx"] + f["sy"] + f["lv"] + list(f["vx"]) + list(f["vy"]) + [f["line"], f["word"], f["fade"]] for f in frames]
    return np.array(rows, dtype=np.int16), len(frames[0]["vx"])


def build_aurora(light, base_q, v, zx0pack, work):
    """(held idx, palette, r0, r1, blob, offsets, stats) for variant settings `v` from the float light frames."""
    if v.get("halo"):
        light = halo.lock(light)
    pts, counts = pm.histogram(light)
    pal = pm.build(pts, counts, 256, 0.5)
    idx = pm.quantise(light, pal)
    err = pm.error(light, idx, pal)
    r0, r1 = pk.band_rows(idx, v["step"])
    stored = pk.stored_rows(idx, r0, r1, v["step"]).copy()
    fixed = pk.fit_headroom(stored, pal, pk.headroom(base_q, r0, r1, v["step"]))
    held = pk.hysteresis(stored, pal, v["hold"])
    blob, offs = pk.pack_frames(pk.deltas(held), zx0pack, work)
    return held, pal, r0, r1, blob, offs, dict(cells=len(pts), headroom_fixes=fixed, err_mean=err[0].round(3).tolist(), err_max=err[1].round(2).tolist())


def sky_blob(base_q, zx0pack, work):
    u = base_q.astype("<u2")
    return pk.zx0(((u[..., 0] << 11) | (u[..., 1] << 5) | u[..., 2]).tobytes(), zx0pack, work, "sky.bin")


def stars_and_sound(p, stars, sound, zx0pack, work):
    rec, nv = star_rows(bake_stars(stars, p)[0])
    d = rec.copy()
    d[1:] = rec[1:] - rec[:-1]
    pcm, rate = snd.convert(sound, (len(rec) - 1) / FPS)
    return rec, nv, pk.zx0(d.astype("<i2").tobytes(), zx0pack, work, "stars.bin"), pcm, rate


def load_or_render(p, cleaned, cache, frames):
    if cache and Path(cache).exists():
        z = np.load(cache)
        return z["base"], z["light"]
    base_q, light = render_frames(p, cleaned, "centre", n=frames)
    if cache:
        np.savez(cache, base=base_q, light=light)
    return base_q, light


def bake_fg(p, v, cleaned, base_q, light, zx0pack, work):
    """Variants F / G: their aurora dict (aurora_fg.py)."""
    if v["mode"] == "rowpal":
        return fg.build_rowpal(light, base_q, zx0pack, work)
    return fg.build_direct(light, picture_f(base_scene(cleaned, p), p), base_q, zx0pack, work)


def fg_extra(a, v):
    """The meta constants only F / G have (the cart reads them with @hasDecl; A..E keep their defaults)."""
    return (f"pub const PAL_MODE: u32 = {a['mode']}; // 1 = a 256-entry palette per stored row (palette.bin), 2 = 16-bit deltas, no palette\n"
            f"pub const WORDMARK: u32 = {v['wordmark']}; // 2 = the name is the baked image word.bin (aurora_word.py), 0 = none\n")


def word_file(rec, nv, n_stars, p):
    """word.bin: the name about 2/3 of the falcon's wingspan at the hold (a script's loops make it tall), centred where the lab centres it (0.86 of H)."""
    k = min(len(rec) - 1, int(round(beats(p).e1 * FPS)))
    vx = rec[k, 3 * n_stars:3 * n_stars + nv] / 16.0  # Q4 pixels
    blob, *_ = word.bake(FONT, float(vx.max() - vx.min()) * 0.65, 160, 0.86 * 200)
    return blob


def bake(settings, photo, out, zx0pack, frames=None, variant="main", sound=None, cache=None):
    p = load_settings(settings)
    v = VARIANTS[variant]
    if "edge" in v:
        p = dict(p, edge=v["edge"])
    stars, cleaned = extract(resize_cover(photo), p["starThr"], band=(p["bandTop"], p["bandBot"]))
    base_q, light = load_or_render(p, cleaned, cache, frames)
    if "mode" in v:
        return bake_set(p, v, variant, stars, (cleaned, base_q, light), out, zx0pack, sound)
    with tempfile.TemporaryDirectory() as work:
        held, pal, r0, r1, blob, offs, stats = build_aurora(light, base_q, v, zx0pack, work)
        rec, nv, stars_zx, pcm, rate = stars_and_sound(p, stars, sound, zx0pack, work)
        sky = sky_blob(base_q, zx0pack, work)
        files = {"aurora.zx0": blob, "aurora.idx": offs, "sky.zx0": sky, "stars.zx0": stars_zx}
        sizes = dict(aurora=len(blob) + len(offs), sky=len(sky), stars=len(stars_zx), sound=len(pcm))
        if variant == "main":
            files["boot.raw"] = pcm.tobytes()  # the sound is shared: only the main set carries it
    words = pk.pixel_palette(pal)
    meta = dict(n_stars=len(stars), nv=nv, rec=rec.shape[1], star_frames=len(rec), aurora_frames=len(held),
                band_y0=r0, band_rows=held.shape[1], edges=EDGES, palette=words, sample_rate=rate, sample_len=len(pcm),
                aurora_at=int(round(beats(p).a0 * FPS)), sizes=sizes, row_step=v["step"])
    n = len(held)
    probes = dict(aurora=sorted({0, n // 4, n // 2, 3 * n // 4, n - 1}), stars=sorted({0, 40, 100, 160, 200} & set(range(len(rec)))))
    ref = em.reference(base_q, words, held, r0, rec, meta, probes)
    ref["stats"] = stats | dict(stars=len(stars), palette=len(pal), band=[r0, r1], variant=variant, hold=v["hold"], row_step=v["step"])
    ref["pcm_md5"] = em.md5(pcm)
    ref["fade_in_frames"] = int(round(p["fadeInSky"] * 60))  # 60 Hz cart frames from black (TC_FADE 31) to 0
    em.write_assets(out, files, meta)
    (Path(out) / "aurora_ref.json").write_text(json.dumps(ref, indent=1, sort_keys=True))
    return ref


def bake_set(p, v, variant, stars, frames3, out, zx0pack, sound):
    """F / G: the same files as the other variants, their aurora from aurora_fg.py, the reference from their own planes."""
    cleaned, base_q, light = frames3
    with tempfile.TemporaryDirectory() as work:
        a = bake_fg(p, v, cleaned, base_q, light, zx0pack, work)
        rec, nv, stars_zx, pcm, rate = stars_and_sound(p, stars, sound, zx0pack, work)
        sky = sky_blob(base_q, zx0pack, work)
    files = {"aurora.zx0": a["blob"], "aurora.idx": a["offs"], "sky.zx0": sky, "stars.zx0": stars_zx} | a["files"]
    if v["wordmark"] == 2:
        files["word.bin"] = word_file(rec, nv, len(stars), p)
    sizes = dict(aurora=len(a["blob"]) + len(a["offs"]) + sum(len(b) for b in a["files"].values()), sky=len(sky), stars=len(stars_zx), sound=len(pcm))
    meta = dict(n_stars=len(stars), nv=nv, rec=rec.shape[1], star_frames=len(rec), aurora_frames=a["n"], band_y0=a["r0"], band_rows=a["rows"],
                edges=EDGES, palette=[0] * 256, sample_rate=rate, sample_len=len(pcm), aurora_at=int(round(beats(p).a0 * FPS)), sizes=sizes,
                row_step=1, extra=fg_extra(a, v))
    probes = dict(stars=sorted({0, 40, 100, 160, 200} & set(range(len(rec)))))
    ref = em.reference_planes(a["planes"], a["sky"], rec, meta, probes)
    ref["stats"] = a["stats"] | dict(stars=len(stars), band=[a["r0"], a["r0"] + a["rows"]], variant=variant, mode=v["mode"], edge=p["edge"])
    ref["pcm_md5"] = em.md5(pcm)
    ref["fade_in_frames"] = int(round(p["fadeInSky"] * 60))
    em.write_assets(out, files, meta)
    (Path(out) / "aurora_ref.json").write_text(json.dumps(ref, indent=1, sort_keys=True))
    return ref


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--variant", choices=sorted(VARIANTS), default="main")
    ap.add_argument("--settings", default=str(HERE / "aurora_settings.json"))
    ap.add_argument("--photo", default=str(ASSETS / "aurora_boot/stars2.jpg"))
    ap.add_argument("--sound", default=str(ASSETS / "aurora_boot/boot_northern_lights_8s5.wav"))
    ap.add_argument("--out", default=None)
    ap.add_argument("--zx0pack", default=str(ROOT / "zig-out/bin/zx0pack"))
    ap.add_argument("--frames", type=int, default=None, help="aurora frames to render (default: all)")
    ap.add_argument("--cache", default=None, help="a .npz of the rendered light: reused if present, else written")
    a = ap.parse_args(argv)
    out = a.out or str(ASSETS / ("aurora_boot" if a.variant == "main" else f"aurora_boot_{a.variant}"))
    ref = bake(a.settings, a.photo, out, a.zx0pack, a.frames, a.variant, a.sound, a.cache)
    print(json.dumps(dict(sizes=ref["sizes"], stats=ref["stats"]), indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
