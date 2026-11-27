"""The boot screen's asset set, from the settings, the stars and the rendered light (aurora_bake.py hands them over).

The aurora as change masks (aurora_direct.py, aurora_mask.py), the star plane baked per 60 Hz frame (overlay.bin,
aurora_overlay.py) with the name as a baked script image (word.bin, aurora_word.py), the sky (ZX0), the sound.
"""
import json
import tempfile
from pathlib import Path

import numpy as np

import aurora_direct as direct
import aurora_emit as em
import aurora_overlay as ov
import aurora_pack as pk
import aurora_sound as snd
import aurora_word as word
import aurora_common as ac
from aurora_common import FPS, beats
from aurora_falcon import EDGES
from aurora_frames import base_scene
from aurora_post import picture_f
from aurora_stars import bake_stars

OVERLAY_PROBES = (100, 330, 400, 480)  # 60 Hz frames whose baked star plane the harness pins (flight, wire, name, fade)


def star_rows(frames):
    """(records, nv): one i16 row per 30 fps frame: sx[N] sy[N] lv[N] vx[NV] vy[NV] line word fade."""
    rows = [f["sx"] + f["sy"] + f["lv"] + list(f["vx"]) + list(f["vy"]) + [f["line"], f["word"], f["fade"]] for f in frames]
    return np.array(rows, dtype=np.int16), len(frames[0]["vx"])


def sky_blob(base_q, zx0pack, work):
    return pk.zx0(direct.words(base_q).astype("<u2").tobytes(), zx0pack, work, "sky.bin")


def word_file(rec, nv, n_stars, p, font, scale):
    """word.bin: the name `scale` of the falcon's wingspan at the hold, centred where the lab centres it (0.86 of H)."""
    k = min(len(rec) - 1, int(round(beats(p).e1 * FPS)))
    vx = rec[k, 3 * n_stars:3 * n_stars + nv] / 16.0  # Q4 pixels
    blob, *_ = word.bake(font, float(vx.max() - vx.min()) * scale, ac.W / 2, 0.86 * ac.H, (ac.W, ac.H))
    return blob


def overlay_files(rec, nv, n_stars, word_blob, a):
    """overlay.bin, the extra meta (scalars, the aurora's delta table) and the probes' plane-1 md5."""
    last = (len(rec) - 1) * 2
    blob, shots = ov.bake(rec, n_stars, nv, EDGES, ov.parse_word(word_blob), last, OVERLAY_PROBES)
    extra = ov.meta_source(ov.scalars(rec, n_stars, nv), a["deltas"])
    return blob, extra, {str(f): em.md5(s) for f, s in shots.items()}


def bake_set(p, stars, frames3, out, zx0pack, sound, font, word_scale):
    """Writes every asset into `out` and returns the reference (aurora_ref.json)."""
    cleaned, base_q, light = frames3
    a = direct.build_direct(light, picture_f(base_scene(cleaned, p), p), base_q)
    rec, nv = star_rows(bake_stars(stars, p)[0])
    pcm, rate = snd.convert(sound, (len(rec) - 1) / FPS)
    with tempfile.TemporaryDirectory() as work:
        sky = sky_blob(base_q, zx0pack, work)
    word_blob = word_file(rec, nv, len(stars), p, font, word_scale)
    overlay, extra, overlay_md5 = overlay_files(rec, nv, len(stars), word_blob, a)
    files = {"aurora.msk": a["blob"], "aurora.idx": a["offs"], "sky.zx0": sky, "word.bin": word_blob, "overlay.bin": overlay,
             "boot.raw": pcm.tobytes()}
    sizes = dict(aurora=len(a["blob"]) + len(a["offs"]), sky=len(sky), stars=len(overlay), sound=len(pcm))
    meta = dict(n_stars=len(stars), star_frames=len(rec), aurora_frames=a["n"], band_y0=a["r0"], band_rows=a["rows"],
                sample_rate=rate, sample_len=len(pcm), aurora_at=int(round(beats(p).a0 * FPS)), sizes=sizes, extra=extra)
    ref = reference(a, rec, meta, pcm, p, word_blob, overlay_md5)
    em.write_assets(out, files, meta)
    (Path(out) / "aurora_ref.json").write_text(json.dumps(ref, indent=1, sort_keys=True))
    return ref


def reference(a, rec, meta, pcm, p, word_blob, overlay_md5):
    """The harness's reference: the probed planes, the star pixels, the sound, the name's size, plane 1's md5s."""
    probes = dict(stars=sorted({0, 40, 100, 160, 200} & set(range(len(rec)))))
    ref = em.reference_planes(a["planes"], a["sky"], rec, meta, probes)
    ref["stats"] = a["stats"] | dict(stars=meta["n_stars"], band=[a["r0"], a["r0"] + a["rows"]], edge=p["edge"])
    ref["pcm_md5"] = em.md5(pcm)
    ref["fade_in_frames"] = int(round(p["fadeInSky"] * 60))  # 60 Hz cart frames from black (TC_FADE 31) to 0
    ref["word_px"] = int(np.count_nonzero(np.frombuffer(word_blob[8:], np.uint8)))
    ref["overlay_md5"] = overlay_md5
    return ref
