"""Variants F / G: their asset set (aurora_bake.py hands over the settings, the stars and the rendered light).

F ships the star records (stars.zx0) and the cart draws them; G ships the star plane baked per 60 Hz frame
(overlay.bin, aurora_overlay.py) and its aurora as change masks (aurora_mask.py). Both draw the name as a baked
script image (word.bin, aurora_word.py).
"""
import json
import tempfile
from pathlib import Path

import numpy as np

import aurora_emit as em
import aurora_fg as fg
import aurora_overlay as ov
import aurora_word as word
from aurora_common import FPS, beats
from aurora_falcon import EDGES
from aurora_frames import base_scene
from aurora_post import picture_f

OVERLAY_PROBES = (100, 330, 400, 480)  # 60 Hz frames whose baked star plane the harness pins (flight, wire, name, fade)


def bake_fg(p, v, cleaned, base_q, light, zx0pack, work):
    """The aurora dict (aurora_fg.py)."""
    if v["mode"] == "rowpal":
        return fg.build_rowpal(light, base_q, zx0pack, work)
    return fg.build_direct(light, picture_f(base_scene(cleaned, p), p), base_q)


def fg_extra(a, v):
    """The meta constants only F / G have (the cart reads them with @hasDecl; A..E keep their defaults)."""
    return (f"pub const PAL_MODE: u32 = {a['mode']}; // 1 = a 256-entry palette per stored row (palette.bin), 2 = 16-bit deltas, no palette\n"
            f"pub const WORDMARK: u32 = {v['wordmark']}; // 2 = the name is the baked image word.bin (aurora_word.py), 0 = none\n")


def word_file(rec, nv, n_stars, p, font, scale):
    """word.bin: the name `scale` of the falcon's wingspan at the hold, centred where the lab centres it (0.86 of H)."""
    k = min(len(rec) - 1, int(round(beats(p).e1 * FPS)))
    vx = rec[k, 3 * n_stars:3 * n_stars + nv] / 16.0  # Q4 pixels
    blob, *_ = word.bake(font, float(vx.max() - vx.min()) * scale, 160, 0.86 * 200)
    return blob


def overlay_files(rec, nv, n_stars, word_blob, a):
    """G: overlay.bin, the extra meta (scalars, the aurora's delta table) and the probes' plane-1 md5."""
    last = (len(rec) - 1) * 2
    blob, shots = ov.bake(rec, n_stars, nv, EDGES, ov.parse_word(word_blob), last, OVERLAY_PROBES)
    extra = ov.meta_source(ov.scalars(rec, n_stars, nv), a["deltas"])
    return {"overlay.bin": blob}, extra, {str(f): em.md5(s) for f, s in shots.items()}


def bake_set(p, v, variant, stars, frames3, out, zx0pack, sound, bake):
    """The same files as the other variants, the aurora from aurora_fg.py, the reference from their own planes.
    `bake` carries the baker's shared stages (stars_and_sound, sky_blob) and the font."""
    cleaned, base_q, light = frames3
    with tempfile.TemporaryDirectory() as work:
        a = bake_fg(p, v, cleaned, base_q, light, zx0pack, work)
        rec, nv, stars_zx, pcm, rate = bake["stars_and_sound"](p, stars, sound, zx0pack, work)
        sky = bake["sky_blob"](base_q, zx0pack, work)
    aurora = "aurora.msk" if v["mode"] == "direct" else "aurora.zx0"  # G's containers are change masks, not ZX0
    files = {aurora: a["blob"], "aurora.idx": a["offs"], "sky.zx0": sky} | a["files"]
    word_blob = word_file(rec, nv, len(stars), p, bake["font"], v["word_scale"])
    files["word.bin"] = word_blob
    extra, overlay_md5 = fg_extra(a, v), {}
    if v["mode"] == "direct":
        more, ov_extra, overlay_md5 = overlay_files(rec, nv, len(stars), word_blob, a)
        files |= more
        extra += ov_extra
        for stale in ("stars.zx0", "aurora.zx0"):  # G ships the baked plane and the masks instead
            (Path(out) / stale).unlink(missing_ok=True)
    else:
        files["stars.zx0"] = stars_zx
    sizes = dict(aurora=len(a["blob"]) + len(a["offs"]) + sum(len(b) for b in a["files"].values()), sky=len(sky),
                 stars=len(files.get("overlay.bin", stars_zx)), sound=len(pcm))
    meta = dict(n_stars=len(stars), nv=nv, rec=rec.shape[1], star_frames=len(rec), aurora_frames=a["n"], band_y0=a["r0"], band_rows=a["rows"],
                edges=EDGES, palette=[0] * 256, sample_rate=rate, sample_len=len(pcm), aurora_at=int(round(beats(p).a0 * FPS)), sizes=sizes,
                row_step=1, extra=extra)
    probes = dict(stars=sorted({0, 40, 100, 160, 200} & set(range(len(rec)))))
    ref = em.reference_planes(a["planes"], a["sky"], rec, meta, probes)
    ref["stats"] = a["stats"] | dict(stars=len(stars), band=[a["r0"], a["r0"] + a["rows"]], variant=variant, mode=v["mode"], edge=p["edge"])
    ref["pcm_md5"] = em.md5(pcm)
    ref["fade_in_frames"] = int(round(p["fadeInSky"] * 60))
    ref["word_px"] = int(np.count_nonzero(np.frombuffer(word_blob[8:], np.uint8)))
    if overlay_md5:
        ref["overlay_md5"] = overlay_md5
    em.write_assets(out, files, meta)
    (Path(out) / "aurora_ref.json").write_text(json.dumps(ref, indent=1, sort_keys=True))
    return ref
