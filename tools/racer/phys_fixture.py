"""Reference fixtures for Kestrel Racing's physics (R82 M2): the Lua engine's per-tick player state, as binary.

The M0 harness (ref_harness.py: freds72's physics under z8lua, local-only) runs the generated oval with no other
car for two scripted inputs: `lap` (the harness' autopilot, 1,500 ticks: a whole lap, 120 segments, reached at tick
~1,390; recorded and replayed as plain buttons, so the Zig port never needs the autopilot) and `wall` (600 ticks of
accelerate + right, into the outer wall). Both slide. The results are committed under apps/zig/assets/screens/racer/
so the native tests and the lap v1 benchmark need neither z8lua nor the engine source:

    python3 tools/racer/phys_fixture.py            # (re)write the fixtures
    python3 tools/racer/phys_fixture.py --check    # exit 1 if the committed files differ from a fresh run

File: u32 magic "RPHY", u32 ticks, then per tick 15 little-endian i32: btn, hits, px py pz vx vy vz angle face u
(raw 16.16 as signed ints), v, tr (the wheel turn), sa (the steering angle), slide (0 / 1: the engine's `sliding`
argument of update_parts). The dump of car 0 only; tick 1 first (the engine's countdown, 90 ticks of no control, is
part of the run).

`lap_v1.btn` is the benchmark's input stream: the lap's buttons from tick 90 (control starts there), 360 ticks (90..449), one
byte a tick. The cart embeds that, not the 90 KB fixture.
"""

from __future__ import annotations

import argparse
import struct
import sys
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from racer import gen_track, ref_harness  # noqa: E402

MAGIC = 0x59485052  # "RPHY"
TICKS = {"lap": 1500, "wall": 600}
LAP_V1 = (ref_harness.COUNTDOWN - 1, 360)  # first row (tick 90, the first with control) and length of the bench stream
COLS = ("btn", "hits", "px", "py", "pz", "vx", "vy", "vz", "angle", "face", "u", "v", "tr", "sa", "slide")
ASSETS = Path(__file__).resolve().parents[2] / "apps/zig/assets/screens/racer"
NAMES = {"lap": "phys_lap.bin", "wall": "phys_wall.bin"}
BTN_NAME = "lap_v1.btn"
ROW = 4 * len(COLS)


def run_player(scenario: str) -> list[dict[str, int]]:
    """The player's rows for `scenario` (npcs = 0: no contact forces, so the stream is the whole input)."""
    doc = gen_track.build_oval()
    ticks = TICKS[scenario]
    dump = ref_harness.run(doc, scenario, ticks, npcs=0)
    rows = [r for r in ref_harness.parse(dump) if r["car"] == 0]
    if scenario == "lap":  # replay the recorded buttons: the stream is then data, not the autopilot
        replay = ref_harness.run(doc, "replay", ticks, npcs=0, inputs=[r["btn"] for r in rows])
        if replay != dump:
            raise RuntimeError("replaying the autopilot's buttons does not reproduce the dump")
    return rows


def pack(rows: list[dict[str, int]]) -> bytes:
    out = struct.pack("<II", MAGIC, len(rows))
    for r in rows:
        out += struct.pack(f"<{len(COLS)}i", *(r[c] for c in COLS))
    return out


def unpack(blob: bytes) -> list[dict[str, int]]:
    magic, n = struct.unpack_from("<II", blob)
    if magic != MAGIC or len(blob) != 8 + n * ROW:
        raise ValueError("not a phys fixture")
    return [dict(zip(COLS, struct.unpack_from(f"<{len(COLS)}i", blob, 8 + ROW * i), strict=True)) for i in range(n)]


def bench_stream(rows: list[dict[str, int]]) -> bytes:
    start, n = LAP_V1
    return bytes(r["btn"] for r in rows[start:start + n])


def expected() -> dict[str, bytes]:
    """Every committed file's bytes as a fresh reference run writes them."""
    out = {}
    for scenario, name in NAMES.items():
        rows = run_player(scenario)
        out[name] = pack(rows)
        if scenario == "lap":
            out[BTN_NAME] = bench_stream(rows)
    return out


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args(argv)
    bad = 0
    for name, blob in expected().items():
        path = ASSETS / name
        if args.check:
            if not path.is_file() or path.read_bytes() != blob:
                print(f"phys_fixture: {name} differs from a fresh reference run", file=sys.stderr)
                bad = 1
        else:
            path.write_bytes(blob)
    return bad


if __name__ == "__main__":
    raise SystemExit(main())
