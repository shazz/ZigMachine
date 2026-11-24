"""Reference fixtures for Kestrel Racing's AI cars (R82 M3): the Lua engine's per-tick state of EVERY car, as binary.

The M0 harness (ref_harness.py: freds72's physics under z8lua, local-only) runs the oval's race grid with the NPCs
(`make_npc`: the PID following the racing line) and the player's `update_contacts`. All cars are held until the player's
control starts (the race's grid + countdown; the engine itself lets the NPCs drive from tick 1: a deliberate
difference, M3.md), so cart race tick n is the reference's row 89 + n. Three runs, committed under
apps/zig/assets/screens/racer/ so the native tests and the benchmark need neither z8lua nor the engine source:

    python3 tools/racer/race_fixture.py            # (re)write the fixtures
    python3 tools/racer/race_fixture.py --check    # exit 1 if the committed files differ from a fresh run

  race_npc2.bin  the race scenario with 2 NPCs, 600 ticks, every car's full state every tick
  race_ram.bin   the ram scenario (the player accelerates into NPC 1 parked ahead), 2 NPCs, 300 ticks: contacts fire
  race_full.bin  the race scenario with 7 NPCs, 4,400 ticks (a 3-lap race and more): a CRC-32 per tick of all 8 cars'
                 state, full rows every 100 ticks, and the tick each car's u first passes the finish (3 laps)
  race_v2.btn    the player's buttons in that race (the autopilot, recorded; one byte a tick from race tick 1)

Full / per-tick words, in order: for each car (player first) px py pz vx vy vz angle face u v (raw 16.16 as signed ints,
the face a 1-based id << 16), then the global wall-hit count, contact count (the engine's sfx 53) and NPC hard-brake count;
a full tick adds the player's buttons as a last word.
"""

from __future__ import annotations

import argparse
import struct
import sys
import zlib
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from racer import gen_track, ref_harness  # noqa: E402

MAGIC_FULL = 0x43415252  # "RRAC": every tick, every car
MAGIC_CRC = 0x43524352  # "RCRC": a CRC a tick, sparse rows
CAR_COLS = ("px", "py", "pz", "vx", "vy", "vz", "angle", "face", "u", "v")
SHARED = ("hits", "sfx", "nbrake")
SKIP = ref_harness.COUNTDOWN - 1  # rows before the first controlled tick
LAPS = 3
SPARSE_EVERY = 100
RUNS = {"race_npc2.bin": ("race", 2, 600), "race_ram.bin": ("ram", 2, 300), "race_full.bin": ("race", 7, 4400)}
BTN_NAME = "race_v2.btn"
ASSETS = Path(__file__).resolve().parents[2] / "apps/zig/assets/screens/racer"


def run_ticks(scenario: str, npcs: int, ticks: int) -> list[list[dict[str, int]]]:
    """Per controlled race tick (1-based), the rows of cars 0..npcs."""
    doc = gen_track.build_oval()
    rows = ref_harness.parse(ref_harness.run(doc, scenario, SKIP + ticks, npcs=npcs))
    per: dict[int, list[dict[str, int]]] = {}
    for r in rows:
        if r["tick"] > SKIP:
            per.setdefault(r["tick"] - SKIP, []).append(r)
    return [per[t] for t in range(1, ticks + 1)]


def words(cars: list[dict[str, int]]) -> list[int]:
    """One tick's words: each car's CAR_COLS, then the shared counters of the (any) row."""
    out = [c[k] for c in cars for k in CAR_COLS]
    return out + [cars[0][k] for k in SHARED]


def _pack(ws: list[int]) -> bytes:
    return struct.pack(f"<{len(ws)}i", *ws)


def pack_full(ticks: list[list[dict[str, int]]]) -> bytes:
    n = len(ticks[0])
    head = struct.pack("<4I", MAGIC_FULL, n, len(ticks), len(CAR_COLS) * n + len(SHARED) + 1)
    return head + b"".join(_pack([*words(t), t[0]["btn"]]) for t in ticks)


def finish_ticks(ticks: list[list[dict[str, int]]]) -> list[int]:
    """The race tick each car's track u first passes LAPS laps minus one segment (0 = never): the finish line."""
    n_seg = len(gen_track.build_oval()["racing_line"])
    limit = (LAPS * n_seg - 1) << 16
    fin = [0] * len(ticks[0])
    for t, cars in enumerate(ticks, 1):
        for i, c in enumerate(cars):
            if fin[i] == 0 and c["u"] > limit:
                fin[i] = t
    return fin


def pack_crc(ticks: list[list[dict[str, int]]]) -> bytes:
    n = len(ticks[0])
    wpt = len(CAR_COLS) * n + len(SHARED)
    head = struct.pack("<6I", MAGIC_CRC, n, len(ticks), wpt, SPARSE_EVERY, len(ticks) // SPARSE_EVERY)
    fin = struct.pack(f"<{n}I", *finish_ticks(ticks))
    crcs = struct.pack(f"<{len(ticks)}I", *(zlib.crc32(_pack(words(t))) for t in ticks))
    sparse = b"".join(_pack(words(ticks[k * SPARSE_EVERY - 1])) for k in range(1, len(ticks) // SPARSE_EVERY + 1))
    return head + fin + crcs + sparse


def unpack_crc(blob: bytes) -> dict[str, object]:
    magic, n, nt, wpt, every, ns = struct.unpack_from("<6I", blob)
    if magic != MAGIC_CRC or len(blob) != 24 + 4 * n + 4 * nt + 4 * wpt * ns:
        raise ValueError("not a race CRC fixture")
    fin = list(struct.unpack_from(f"<{n}I", blob, 24))
    crcs = list(struct.unpack_from(f"<{nt}I", blob, 24 + 4 * n))
    return {"cars": n, "ticks": nt, "finish": fin, "crcs": crcs, "every": every}


def expected() -> dict[str, bytes]:
    """Every committed file's bytes as a fresh reference run writes them."""
    out: dict[str, bytes] = {}
    for name, (scenario, npcs, ticks) in RUNS.items():
        t = run_ticks(scenario, npcs, ticks)
        out[name] = pack_crc(t) if name == "race_full.bin" else pack_full(t)
        if name == "race_full.bin":
            out[BTN_NAME] = bytes(c[0]["btn"] for c in t)
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
                print(f"race_fixture: {name} differs from a fresh reference run", file=sys.stderr)
                bad = 1
        else:
            path.write_bytes(blob)
    return bad


if __name__ == "__main__":
    raise SystemExit(main())
