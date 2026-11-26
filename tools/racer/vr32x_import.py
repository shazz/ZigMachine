"""LOCAL ONLY: the five Virtua Racing Deluxe (32X) courses from the user's own cartridge dump -> our track files, to benchmark.

    python3 -I tools/racer/vr32x_import.py [--rom <VirtuaRacingDX.32x>] [--out <dir>] [--tracks 3,4] [--allow-soft]

Same rule as tools/racer/vr_import.py: this script holds NO data, the dump stays where the user put it, and everything it
writes (`vr32x_<n>.ktrk.json`, `vr32x_<n>.ktrk`, `vr32x_report.txt`) goes to the git-ignored
prototypes/racer_re/vr_local/32x/ and is never committed or put on a shared card.

Pipeline: vr32x_rom (the tile models, the race palette) -> vr32x_geom (one welded mesh, kinds, decals, borders) ->
vr32x_line (a racing line walked on the asphalt: SYNTHESISED, the 32X's own course tables are not decoded) -> the grid as
vr_import's (synthesised) -> trackc.convert with a mood block. Colours: each face is its palette entry, solid and unlit (the
32X draws flat colours); the entries (100+ a track) go on the cart's 23 free ramps: the road and the far ground first, then
greedily the entry worst served so far (weighted by face area), the rest on the nearest (ramp, level) shade
(vr_colours.lit). The budget check (budget.py) runs and is REPORTED; its SOFT overruns are refused unless --allow-soft.
"""

from __future__ import annotations

import argparse
import math
import sys
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from racer import (  # noqa: E402
    budget, ktrk, limits, mood, trackc, vr32x_cells, vr32x_colours, vr32x_course, vr32x_decoded, vr32x_find, vr32x_geom, vr32x_line,
    vr32x_feel, vr32x_rom, vr32x_walk, vr_colours, vr_import,
)

WALK_SEEDS = 6  # seeds the walk starts from, each way (the shortest laps use them all)
SEGMENT_LEN = 3.5  # units of racing line a segment (freds72's tracks: 3.4-3.6)
BUFFER = 738 * 1024  # the track buffer as the stress city sizes it (M5.md "One buffer"); a bigger file grows it ...
MAX_FILE = 1 << 20  # ... up to library.MAX_FILE, if the RAM window has the room (the node check decides)
RGB = vr32x_rom.RGB


def _face(f: vr32x_geom.Face) -> ktrk.Doc:
    out: ktrk.Doc = {"v": f.v, "kind": f.kind, "mat": f"c{f.colour:02x}"}
    if f.dual:
        out["dual"] = True
    if f.borders:
        out["borders"] = sorted(f.borders)
    if f.inner:
        out["inner"] = [{"v": g.v, "mat": f"c{g.colour:02x}"} for g in f.inner]
    return out


def line(m: vr32x_geom.Mesh, bins: vr32x_geom.Bins, info: dict[str, object]) -> list[dict[str, int]]:
    """The racing line: the longest closed candidate that does not double back (shortest laps and walks from seeds
    spread over the asphalt), smoothed and resampled, its edge points appended as vertices."""
    cells = vr32x_cells.Cells(bins)
    walks = [("lap", w) for w in vr32x_line.laps(m, bins, cells)]
    for c, hd in vr32x_line.seeds(m, WALK_SEEDS):
        for sign in (1, -1):
            try:
                walks.append(("walk", vr32x_walk.walk(bins, cells, c, math.atan2(sign * hd[0], sign * hd[1]))))
            except vr32x_line.LineError:
                continue
    if not walks:
        raise vr32x_line.LineError("no closed walk on the asphalt from any seed")
    good = [w for w in walks if vr32x_line.overlap(w[1]) <= 0.1] or walks
    how, raw = max(good, key=lambda w: vr32x_line.length(w[1]))
    info["line"] = (f"{how} of {vr32x_line.length(raw):.0f} units (of {sum(1 for w in walks if w[0] == 'lap')} laps, "
                    f"{sum(1 for w in walks if w[0] == 'walk')} walks: {sorted(round(vr32x_line.length(w[1])) for w in good)})")
    best = vr32x_line.smooth(raw)
    n = min(limits.MAX_SEGMENTS, round(vr32x_line.length(best) / SEGMENT_LEN))
    seg = []
    for left, right in vr32x_line.resample(best, n):
        ids = []
        for p in (left, right):
            ids.append(len(m.verts))
            m.verts.append([ktrk.q(c) for c in p])
        seg.append({"l": ids[0], "r": ids[1]})
    return seg


def build(rom: bytes, k: int, dec: vr32x_decoded.Decoded | None) -> tuple[ktrk.Doc, dict[str, object], vr32x_geom.Mesh, list[RGB]]:
    pal = vr32x_rom.palette(rom, k)
    m = vr32x_geom.build(vr32x_rom.tiles(rom, k), pal)
    bins = vr32x_geom.Bins(m)
    info: dict[str, object] = dict(m.stats)
    info["decals"] = vr32x_geom.decals(m, bins)
    if dec is not None:
        seg, cps, grid = vr32x_decoded.apply(m, bins, info, dec)
        info.update(vr32x_decoded.check(bins, dec, grid))
        info["line"] = (f"DECODED: {len(seg)} course points, lap {info['lap']:.0f} units, "
                        f"{'clockwise' if info['clockwise'] else 'anticlockwise'}, {info['pit']} pit-lane points; "
                        f"kinds {info['kinds']}, path points off our asphalt {info['path_off_asphalt']}")
    else:
        info["borders"] = vr32x_geom.borders(m, bins)
        seg = line(m, bins, info)
        cps, grid = [len(seg) // 3, 2 * len(seg) // 3, len(seg) - 1], vr_import.grid(m.verts, seg)
    faces = [_face(f) for f in m.faces if f.parent < 0]
    vs = m.verts
    doc = {"format": "ktrk-json", "version": 1, "name": f"vr32x_{vr32x_rom.TRACKS[k]}", "tile_size": ktrk.TILE,
           "grid": [32, 32], "vertex_scale": ktrk.SCALE, "vertices": vs,
           "materials": sorted({f["mat"] for f in faces} | {i["mat"] for f in faces for i in f.get("inner", [])}),
           "faces": faces, "racing_line": seg, "checkpoints": cps,
           "start_grid": grid, "generator": {"kind": "vr32x_local", "course": "decoded" if dec else "synthesised"}}
    return doc, info, m, pal


def clockwise(doc: ktrk.Doc) -> ktrk.Doc:
    """Run the line clockwise seen from above (+z up the page), as freds72's three tracks all do: the Deluxe-only courses'
    direction is NOT known from the dump, this is the same sense as the arcade three."""
    vs, seg = doc["vertices"], doc["racing_line"]
    mid = [((vs[s["l"]][0] + vs[s["r"]][0]) / 2, (vs[s["l"]][2] + vs[s["r"]][2]) / 2) for s in seg]
    if sum(mid[i - 1][0] * mid[i][1] - mid[i][0] * mid[i - 1][1] for i in range(len(mid))) > 0:
        seg = [{"l": s["r"], "r": s["l"]} for s in reversed(seg)]
        doc["racing_line"], doc["start_grid"] = seg, vr_import.grid(vs, seg)
    return doc


def report(k: int, doc: ktrk.Doc, info: dict[str, object], blob: bytes, cols: vr32x_colours.Cols, pal: list[RGB],
           area: dict[int, float]) -> list[str]:
    m, (at, rgb) = budget.meter(doc), cols
    how = "DECODED" if doc["generator"]["course"] == "decoded" else "SYNTHESISED"
    errs, total = vr32x_colours.errors(pal, at, rgb), sum(area.values()) or 1.0
    shaded = sorted((c for c, (_, lv) in at.items() if lv != vr_colours.FLAT), key=lambda c: -area[c])
    fit = ("fits" if len(blob) <= BUFFER else f"is {len(blob) - BUFFER} bytes over") + f" the {BUFFER // 1024} KB buffer"
    fit += " the city sizes, " + ("under" if len(blob) <= MAX_FILE else "OVER") + " library.MAX_FILE (1 MiB)"
    return [f"vr32x_{k + 1} {vr32x_rom.TRACKS[k]}: {m.vertices} vertices ({len(doc['racing_line']) * 2} of them the line's), "
            f"{len(doc['faces'])} faces + {m.faces - len(doc['faces'])} decals = {m.faces} drawn, busiest tile {m.busiest_tile} "
            f"at {m.busiest_at}, {len(ktrk.tile_faces(doc))} tiles used, {len(doc['racing_line'])} segments ({how}), "
            f"checkpoints {doc['checkpoints']}, grid ({how}) on segments {sorted({g['segment'] for g in doc['start_grid']})}",
            f"  geometry: {info['split_quads']} non-flat/concave quads split, {info['dropped_degenerate']} degenerate dropped, "
            f"{info['decals']} decals attached, {info['borders']} border edges; line: {info['line']}",
            f"  colours: {len(at)} palette entries -> {len({r for r, _ in at.values()})} ramps; area-weighted RGB error "
            f"{sum(errs[c] * area[c] for c in at) / total:.1f}, worst {max(errs.values()):.0f}; shaded on a ramp (by area): "
            + ", ".join(f"{c:02x}(err {errs[c]:.0f})" for c in shaded[:10])
            + (" ..." if len(shaded) > 10 else ""),
            f"  binary {len(blob)} bytes: {fit}; budget: "
            + ("; ".join(p for p in budget.problems(doc) if "colour ramps" not in p) or "within every limit")]


def run(rom: bytes, k: int, out: Path, allow_soft: bool, dec: vr32x_decoded.Decoded | None, headroom: bool = False) -> list[str]:
    doc, info, m, pal = build(rom, k, dec)
    doc = clockwise(doc) if dec is None else doc  # decoded: the 32X's own direction
    probs = [p for p in budget.problems(doc) if "colour ramps" not in p]  # the entries are merged onto 23 ramps below
    if any(p.startswith("HARD") for p in probs) or (probs and not allow_soft):
        raise trackc.ConvertError("; ".join(probs) + ("" if allow_soft else " (--allow-soft converts past SOFT limits)"))
    if any(len(f.get("inner", [])) > 255 for f in doc["faces"]):
        raise trackc.ConvertError("a face has more than 255 decals (a u8 in the face record)")
    at, rgb, area = vr32x_colours.colours(m, pal)
    (out / f"vr32x_{k + 1}.ktrk.json").write_text(ktrk.dumps(doc))
    look = vr32x_feel.apply(doc, dec[0] if dec else None)  # R82 32X feel: the arcade scales and the AI's cues
    blob = trackc.convert(doc, vr32x_colours.mats(rgb), validate=False, shade=vr_colours.shader(at, headroom), look=look)
    (out / f"vr32x_{k + 1}.ktrk").write_bytes(blob)
    return report(k, doc, info, blob, (at, rgb), pal, area)


def main(argv: list[str] | None = None) -> int:
    root = vr_import._root()
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--rom", default=str(root / "prototypes/racer_re/vr_local/32x/VirtuaRacingDX.32x"))
    ap.add_argument("--out", default=str(root / "prototypes/racer_re/vr_local/32x"))
    ap.add_argument("--tracks", default="1,2,3,4,5",
                    help="1-based: 1 Big Forest, 2 Bay Bridge, 3 Acropolis, 4 Highland, 5 Sand Park")
    ap.add_argument("--allow-soft", action="store_true", help="convert a track over a SOFT budget limit (still reported)")
    ap.add_argument("--synth", action="store_true", help="synthesise the line, checkpoints, grid and walls from the geometry "
                    "(the old way) instead of decoding the 68000's course tables")
    ap.add_argument("--shadow-headroom", action="store_true", help="store each face's colour kept off its ramp's bottom "
                    "too (the cart's shadow headroom toggle, key 9 / the SHADOW row: FEEL.md)")
    args = ap.parse_args(argv)
    rom, out = vr32x_rom.load(Path(args.rom)), Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    decs = None if args.synth else vr32x_find.tracks(rom, len(vr32x_rom.TRACKS))  # raises if a table is not found
    lines: list[str] = []
    for k in (int(t) - 1 for t in args.tracks.split(",")):
        try:
            got = run(rom, k, out, args.allow_soft, decs[k] if decs else None, args.shadow_headroom)
        except (trackc.ConvertError, vr32x_line.LineError, vr32x_rom.RomError, vr32x_course.CourseError,
                vr32x_decoded.DecodeError) as e:
            got = [f"vr32x_{k + 1} {vr32x_rom.TRACKS[k]}: NOT CONVERTED: {e}"]
        lines += got
        print("\n".join(got), flush=True)
    (out / "vr32x_report.txt").write_text("\n".join(lines) + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
