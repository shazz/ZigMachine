"""LOCAL ONLY: freds72's decoded Virtua Racing tracks -> our track binary (`-Dracer_vr=true`), for benchmarking.

    python3 -I tools/racer/vr_import.py [--src <freds72_src/carts>] [--out <dir>]

The data is derived from Sega's Mega Drive game: this script holds none, writes only under a git-ignored directory
(default <main checkout>/prototypes/racer_re/vr_local/), and nothing it writes may ever be committed. Per track N (1..3)
it writes `vr_N.ktrk.json` (our intermediate) and `vr_N.ktrk` (the converter's v3 binary) plus `vr_report.txt` (the budgets).

Mapping: a face's PICO-8 colour byte (low nibble / high nibble: the engine's dither pair) becomes the average RGB of the two,
merged to the nearest ramp when a track uses more colours than the palette has ramps (ramps 0-11 and 19-29: 12-18 are the
cart's car and liveries). Ramp 0 is the road's dominant colour and ramp 1 the track's own ground colour (the cart darkens it beyond the draw distance), as in the oval.
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path
from typing import Any

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from racer import ktrk, trackc, vr_cart  # noqa: E402

PICO = ["000000", "1D2B53", "7E2553", "008751", "AB5236", "5F574F", "C2C3C7", "FFF1E8", "FF004D", "FFA300", "FFEC27",
        "00E436", "29ADFF", "83769C", "FF77A8", "FFCCAA"]
FREE_RAMPS = list(range(0, 12)) + list(range(19, 30))
CAR = {k: v for k, v in trackc.MATERIALS.items() if k.startswith("car_")}
SOLID, NOT_ASPHALT, DUAL = 16, 4, 1


def rgb_of(c: int) -> tuple[int, int, int]:
    a, b = PICO[c & 15], PICO[(c >> 4) & 15]
    return tuple((int(a[i:i + 2], 16) + int(b[i:i + 2], 16)) // 2 for i in (0, 2, 4))  # type: ignore[return-value]  # 3 ints


def _root() -> Path:
    for p in Path(__file__).resolve().parents:
        if (p / "prototypes" / "racer_re").is_dir():
            return p
        if p.parent.name == "worktrees" and p.parent.parent.name == ".claude":
            return p.parent.parent.parent
    return Path.cwd()


def palette(track: dict[str, Any]) -> tuple[dict[int, str], dict[str, tuple[int, tuple[int, int, int]]]]:
    """colour byte -> material name, and the material table (ramp, rgb) incl. the cart's car ramps."""
    uses: dict[int, int] = {}
    for f in track["faces"]:
        for g in [f] + f.get("inner", []):
            uses[g["c"]] = uses.get(g["c"], 0) + 1
    ground = track["ground_color"] | (track["ground_color"] << 4)
    uses[ground] = uses.get(ground, 0) + 1
    road: dict[int, int] = {}
    for f in track["faces"]:
        if f["flags"] & SOLID and not f["flags"] & NOT_ASPHALT:
            road[f["c"]] = road.get(f["c"], 0) + 1
    asphalt = max(road, key=lambda c: road[c]) if road else ground
    first = [asphalt] + ([ground] if ground != asphalt else [])  # ramp 0: the road (the minimap's line), ramp 1: the ground (cart: GROUND_RAMP)
    groups: list[list[int]] = [[c] for c in first] + [[c] for c in sorted(uses, key=lambda c: -uses[c]) if c not in first]
    while len(groups) > len(FREE_RAMPS):  # merge the least used colour into the nearest other group
        small = min(groups[2:], key=lambda g: sum(uses[c] for c in g))
        rest = [g for g in groups if g is not small]
        near = min(rest, key=lambda g: math.dist(rgb_of(g[0]), rgb_of(small[0])))
        near += small
        groups = rest
    mats: dict[str, tuple[int, tuple[int, int, int]]] = dict(CAR)
    names: dict[int, str] = {}
    for ramp, g in zip(FREE_RAMPS, groups, strict=False):
        mats[f"vr{ramp}"] = (ramp, rgb_of(g[0]))
        for c in g:
            names[c] = f"vr{ramp}"
    for ramp in range(15, 19):
        mats[f"pad{ramp}"] = (ramp, (128, 128, 128))
    return names, mats


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
        kind = ("ground" if fl & NOT_ASPHALT else "track") if fl & SOLID else "prop"
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
        names, mats = palette(track)
        doc, extra = build(track, names)
        (out / f"vr_{tid + 1}.ktrk.json").write_text(ktrk.dumps(doc))
        blob = trackc.convert(doc, mats, validate=False)
        (out / f"vr_{tid + 1}.ktrk").write_bytes(blob)
        lines.append(report(tid + 1, track, doc, extra, blob))
    (out / "vr_report.txt").write_text("\n".join(lines) + "\n")
    print("\n".join(lines))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
