"""LOCAL ONLY: freds72's decoded Virtua Racing tracks -> our track binary (`-Dracer_vr=true`), for benchmarking.

    python3 -I tools/racer/vr_import.py [--src <freds72_src/carts>] [--out <dir>]

The data is derived from Sega's Mega Drive game: this script holds none, writes only under a git-ignored directory
(default <main checkout>/prototypes/racer_re/vr_local/), and nothing it writes may ever be committed. Per track N (1..3)
it writes `vr_N.ktrk.json` (our intermediate) and `vr_N.ktrk` (the converter's v3 binary) plus `vr_report.txt` (the budgets).

Colours (tools/racer/vr_colours.py): a face's PICO-8 colour byte (his dither pair) becomes one solid colour, UNLIT as his
engine draws it; each distinct byte owns a ramp (0-11 and 19-29: 12-18 are the cart's car and liveries) at the flat level,
and a track with more bytes than ramps puts the rest on the nearest (ramp, level) shade. Ramp 0 is the road's dominant colour
and ramp 1 the track's own ground colour, as in the oval.
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path
from typing import Any

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from racer import ktrk, mood, trackc, vr_cart, vr_colours  # noqa: E402

FREE_RAMPS = list(range(0, 12)) + list(range(19, 30))
CAR = {k: v for k, v in trackc.MATERIALS.items() if k.startswith("car_")}
SOLID, ASPHALT, DUAL = 16, 4, 1  # his bit 2 SET = asphalt: vracing_main.p8 slows and shakes the car when `flags&0x4==0`
Mats = dict[str, tuple[int, tuple[int, int, int]]]


def _root() -> Path:
    for p in Path(__file__).resolve().parents:
        if (p / "prototypes" / "racer_re").is_dir():
            return p
        if p.parent.name == "worktrees" and p.parent.parent.name == ".claude":
            return p.parent.parent.parent
    return Path.cwd()


def palette(track: dict[str, Any]) -> tuple[dict[int, str], Mats, dict[int, tuple[int, int]]]:
    """colour byte -> material name ("c<byte>"), the palette's material table (ramp, rgb) incl. the cart's car ramps, and
    each byte's (ramp, level) (vr_colours.place)."""
    uses: dict[int, int] = {}
    for f in track["faces"]:
        for g in [f] + f.get("inner", []):
            uses[g["c"]] = uses.get(g["c"], 0) + 1
    ground = track["ground_color"] | (track["ground_color"] << 4)
    uses[ground] = uses.get(ground, 0) + 1
    road: dict[int, int] = {}
    for f in track["faces"]:
        if f["flags"] & SOLID and f["flags"] & ASPHALT:
            road[f["c"]] = road.get(f["c"], 0) + 1
    asphalt = max(road, key=lambda c: road[c]) if road else ground
    lead = [asphalt] + ([ground] if ground != asphalt else [])  # ramp 0: the road (the minimap's line), ramp 1: the ground (cart: GROUND_RAMP)
    at, rgb = vr_colours.place(sorted(uses, key=lambda c: -uses[c]), FREE_RAMPS, lead)
    mats: Mats = dict(CAR)
    for ramp, c in rgb.items():
        mats[f"vr{ramp}"] = (ramp, c)
    for ramp in range(15, 19):
        mats[f"pad{ramp}"] = (ramp, (128, 128, 128))
    return {c: f"c{c:02x}" for c in uses}, mats, at


def merged(at: dict[int, tuple[int, int]]) -> str:
    """The bytes that share a ramp (a shade below the flat level), with their colour error: for the report."""
    out = []
    for c, (ramp, level) in sorted(at.items()):
        if level != vr_colours.FLAT:
            own = next(k for k, (r, lv) in at.items() if r == ramp and lv == vr_colours.FLAT)
            got = tuple(vr_colours.lit(x, level) for x in vr_colours.rgb_of(own))
            out.append(f"{c:02x}->ramp {ramp} level {level} (err {math.dist(got, vr_colours.rgb_of(c)):.0f})")
    return ", ".join(out) or "none"



def _degenerate(vs: list[list[int]], ids: list[int]) -> bool:
    p = ktrk.pts({"vertices": vs}, ids)
    n = ktrk.cross(ktrk.sub(p[-1], p[0]), ktrk.sub(p[1], p[0]))
    return ktrk.dot(n, n) < 1e-9


def build(track: dict[str, Any], names: dict[int, str]) -> tuple[ktrk.Doc, dict[str, int]]:
    vs = [[ktrk.q(c) for c in v] for v in track["verts"]]
    faces, dropped = [], 0
    for f in track["faces"]:
        if _degenerate(vs, f["v"]):
            dropped += 1
            continue
        fl = f["flags"]
        kind = ("track" if fl & ASPHALT else "ground") if fl & SOLID else "prop"
        out: ktrk.Doc = {"v": f["v"], "kind": kind, "mat": names[f["c"]]}
        if fl & DUAL:
            out["dual"] = True
        if f.get("borders"):
            out["borders"] = sorted(set(f["borders"]))
        inner = [{"v": g["v"], "mat": names[g["c"]]} for g in f.get("inner", []) if not _degenerate(vs, g["v"])]
        if inner:
            out["inner"] = inner
        faces.append(out)
    seg = [{"l": a, "r": b} for a, b in track["segments"]]
    cps = [c - 1 for c in track["checkpoints"]]  # his are 1-based Lua indices (the last = #segments)
    doc = {"format": "ktrk-json", "version": 1, "name": f"vr{track['id']}", "tile_size": ktrk.TILE, "grid": [32, 32],
           "vertex_scale": ktrk.SCALE, "vertices": vs, "materials": sorted({f["mat"] for f in faces}), "faces": faces,
           "racing_line": seg, "checkpoints": cps, "start_grid": grid(vs, seg), "generator": {"kind": "vr_local"}}
    return doc, {"dropped_degenerate": dropped}


def grid(vs: list[list[int]], seg: list[dict[str, int]]) -> list[ktrk.Doc]:
    """Eight cars as the oval's grid: the player on segment 0, the AI cars two a row on 1..4, a quarter of the road off the line."""
    mid = [[(vs[s["l"]][k] + vs[s["r"]][k]) / 2 for k in range(3)] for s in seg]
    out = []
    for slot in range(8):
        i = (slot + 1) // 2
        lat = 0.0 if slot == 0 else (0.22 if slot % 2 else -0.22)
        a, b = vs[seg[i]["l"]], vs[seg[i]["r"]]
        pos = [round(mid[i][k] + (b[k] - a[k]) * lat) for k in range(3)]
        nx = mid[(i + 1) % len(mid)]
        yaw = (math.atan2(nx[0] - mid[i][0], nx[2] - mid[i][2]) / (2 * math.pi)) % 1.0
        out.append({"segment": i, "pos": pos, "yaw_q16": int(round(yaw * 65536)) & 0xFFFF})
    return out


def report(tid: int, track: dict[str, Any], doc: ktrk.Doc, extra: dict[str, int], blob: bytes) -> str:
    inner = sum(len(f.get("inner", [])) for f in doc["faces"])
    per = ktrk.tile_faces(doc)
    big = max(len(v) for v in per.values())
    return (f"vr{tid}: {len(doc['vertices'])} vertices, {len(doc['faces'])} faces (+{inner} decals), {len(doc['racing_line'])} segments, "
            f"{len(doc['checkpoints'])} checkpoints, {len(doc['materials'])} colours, {len(per)} tiles used, busiest tile {big} faces, "
            f"{extra['dropped_degenerate']} degenerate faces dropped, binary {len(blob)} bytes")


def main(argv: list[str] | None = None) -> int:
    root = _root()
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--src", default=str(root / "prototypes/racer_re/freds72_src/carts"))
    ap.add_argument("--out", default=str(root / "prototypes/racer_re/vr_local"))
    args = ap.parse_args(argv)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    lines = []
    for tid in range(3):
        track = vr_cart.read_track(Path(args.src), tid)
        names, mats, at = palette(track)
        doc, extra = build(track, names)
        (out / f"vr_{tid + 1}.ktrk.json").write_text(ktrk.dumps(doc))
        blob = trackc.convert(doc, mats, validate=False, shade=vr_colours.shader(at), look=mood.Mood(ground_level=7))  # his far ground: unlit
        (out / f"vr_{tid + 1}.ktrk").write_bytes(blob)
        lines.append(report(tid + 1, track, doc, extra, blob) + f"; tones {vr_colours.TONES}, shaded below a ramp: {merged(at)}")
    (out / "vr_report.txt").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
