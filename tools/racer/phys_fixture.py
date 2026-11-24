"""Reference fixtures for Kestrel Racing's physics (R82 M2): the Lua engine's per-tick player state, as binary.

The M0 harness (ref_harness.py: freds72's physics under z8lua, local-only) runs the generated oval with no other
car for 600 ticks, for two scripted inputs: `lap` (the harness' autopilot, recorded and replayed as plain
buttons, so the Zig port never needs the autopilot) and `wall` (accelerate + right, into the outer wall).
The result is committed under apps/zig/assets/screens/racer/ so the native tests and the lap v1 benchmark need
neither z8lua nor the engine source:

    python3 tools/racer/phys_fixture.py            # (re)write both fixtures
    python3 tools/racer/phys_fixture.py --check    # exit 1 if the committed files differ from a fresh run

File: u32 magic "RPHY", u32 ticks, then per tick 13 little-endian i32: btn, hits, px py pz vx vy vz angle face
u (raw 16.16 as signed ints), v. The dump of car 0 only; tick 1 first (the engine's countdown, 90 ticks of no control,
is part of the 600).
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
TICKS = 600
COLS = ("btn", "hits", "px", "py", "pz", "vx", "vy", "vz", "angle", "face", "u", "v")
ASSETS = Path(__file__).resolve().parents[2] / "apps/zig/assets/screens/racer"
NAMES = {"lap": "phys_lap.bin", "wall": "phys_wall.bin"}


def run_player(scenario: str) -> list[dict[str, int]]:
    """The player's rows for `scenario` (npcs = 0: no contact forces, so the stream is the whole input)."""
    doc = gen_track.build_oval()
    dump = ref_harness.run(doc, scenario, TICKS, npcs=0)
    rows = [r for r in ref_harness.parse(dump) if r["car"] == 0]
    if scenario == "lap":  # replay the recorded buttons: the stream is then data, not the autopilot
        replay = ref_harness.run(doc, "replay", TICKS, npcs=0, inputs=[r["btn"] for r in rows])
        if replay != dump:
            raise RuntimeError("replaying the autopilot's buttons does not reproduce the dump")
    return rows


def pack(rows: list[dict[str, int]]) -> bytes:
    out = struct.pack("<II", MAGIC, len(rows))
    for r in rows:
        out += struct.pack("<12i", *(r[c] for c in COLS))
    return out


def unpack(blob: bytes) -> list[dict[str, int]]:
    magic, n = struct.unpack_from("<II", blob)
    if magic != MAGIC or len(blob) != 8 + n * 48:
        raise ValueError("not a phys fixture")
    return [dict(zip(COLS, struct.unpack_from("<12i", blob, 8 + 48 * i), strict=True)) for i in range(n)]


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args(argv)
    bad = 0
    for scenario, name in NAMES.items():
        blob = pack(run_player(scenario))
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
