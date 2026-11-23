"""Lua reference harness for Kestrel Racing's physics (R82 M0).

freds72's engine functions (MIT, github.com/freds72/virtua-on, `vracing_main.p8`) are read at run time from a
local clone, spliced between our prelude and footer (tools/racer/lua/) and run under z8lua's `pico8` branch
(PICO-8 16.16 numbers, its sin/cos/atan2 tables) on a generated `.ktrk.json` track. Nothing of his is copied
into the repo, and none of his data (tracks, models, maps) is read: only the physics functions are extracted.

Locations (both local-only, under the main checkout's git-ignored prototypes/racer_re/):
    RACER_Z8LUA   path of the z8lua binary         (default <root>/prototypes/racer_re/z8lua/z8lua)
    RACER_FREDS72 path of the freds72_src/ clone   (default <root>/prototypes/racer_re/freds72_src)

    python3 tools/racer/ref_harness.py --track oval.ktrk.json [--scenario lap|wall] [--ticks 600] > dump.tsv
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

if __package__ in (None, ""):
    sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from racer import ktrk, ktrk_lua  # noqa: E402

LUA_DIR = Path(__file__).resolve().parent / "lua"
SRC_FILE = "carts/vracing_main.p8"
FUNCTIONS = (
    "lerp make_v v_clone v_dot v_scale v_add v_len v_normz v_lerp v_cross v2_cross v2_ortho make_q m_from_q "
    "m_x_v m_x_m m_clone make_m_from_euler make_m_from_v_angle m_inv_x_v m_set_pos m_right m_up m_fwd "
    "make_skidmarks make_car make_plyr make_track make_pid make_npc is_inside find_face face_collide"
).split()
LOCAL_LINES = ("local v_up={0,1,0}", "local skidmarks=make_skidmarks()")
COUNTDOWN = 90  # play_state's start_ttl: the player's control starts at tick 90


class HarnessUnavailable(RuntimeError):
    """z8lua or the engine source is not on this machine."""


def _root() -> Path:
    """The main checkout (prototypes/ is git-ignored, so a worktree does not have it)."""
    for p in [Path(__file__).resolve(), *Path(__file__).resolve().parents]:
        if (p / "prototypes" / "racer_re").is_dir():
            return p
        if p.parent.name == "worktrees" and p.parent.parent.name == ".claude":
            return p.parent.parent.parent
    return Path.cwd()


def z8lua_path() -> Path:
    p = Path(os.environ.get("RACER_Z8LUA") or _root() / "prototypes/racer_re/z8lua/z8lua")
    if not p.is_file():
        raise HarnessUnavailable(f"z8lua binary not found at {p} (build: prototypes/racer_re/z8lua/build_local.sh)")
    return p


def source_path() -> Path:
    p = Path(os.environ.get("RACER_FREDS72") or _root() / "prototypes/racer_re/freds72_src") / SRC_FILE
    if not p.is_file():
        raise HarnessUnavailable(f"engine source not found at {p}")
    return p


def extract(text: str, names: list[str] = FUNCTIONS) -> str:
    """The named top-level functions (column-0 `function name(` .. column-0 `end`) plus the LOCAL_LINES."""
    lines = text.split("__gfx__")[0].splitlines()
    out = list(LOCAL_LINES[:1])
    for name in names:
        start = next((i for i, ln in enumerate(lines) if re.match(rf"function {name}\(", ln)), None)
        if start is None:
            raise ValueError(f"function {name} not found in the engine source")
        end = next(i for i in range(start, len(lines)) if lines[i].rstrip() == "end")
        out += lines[start:end + 1]
        if name == "make_skidmarks":
            out.append(LOCAL_LINES[1])
    return "\n".join(out) + "\n"


def assemble(track_lua: str, scenario: str, ticks: int, npcs: int, inputs: list[int] | None) -> str:
    inp = "nil" if inputs is None else "{" + ",".join(str(b) for b in inputs) + "}"
    head = (f'RACER_SCENARIO="{scenario}"\nRACER_TICKS={ticks}\nRACER_NPCS={npcs}\n'
            f"RACER_COUNTDOWN={COUNTDOWN}\nRACER_INPUTS={inp}\n")
    engine = extract(source_path().read_text())
    return "\n".join([head, track_lua, (LUA_DIR / "prelude.lua").read_text(), engine, (LUA_DIR / "footer.lua").read_text()])


def run(doc: ktrk.Doc, scenario: str = "lap", ticks: int = 600, npcs: int = 2,
        inputs: list[int] | None = None) -> str:
    """The per-tick dump (TSV text) of a run. Raises HarnessUnavailable without z8lua / the source."""
    if scenario not in ("lap", "wall", "replay") or (scenario == "replay") != (inputs is not None):
        raise ValueError("scenario must be lap, wall, or replay (with inputs)")
    exe = z8lua_path()
    chunk = assemble(ktrk_lua.to_lua(doc), scenario, ticks, npcs, inputs)
    with tempfile.TemporaryDirectory() as tmp:
        script = Path(tmp) / "racer_ref.lua"
        script.write_text(chunk)
        res = subprocess.run([str(exe), str(script)], capture_output=True, text=True, timeout=120, check=False)
    if res.returncode != 0:
        raise RuntimeError(f"z8lua failed ({res.returncode}): {res.stderr[:500]}")
    return res.stdout


def parse(dump: str) -> list[dict[str, int]]:
    """Dump rows with every 16.16 column as a signed raw int (value * 65536)."""
    rows = []
    lines = dump.strip().splitlines()
    cols = lines[0].split("\t")
    for ln in lines[1:]:
        rec = dict(zip(cols, ln.split("\t"), strict=True))
        row = {k: int(v) for k, v in rec.items() if k in ("tick", "car", "btn", "hits")}
        for k in ("px", "py", "pz", "vx", "vy", "vz", "angle", "face", "u", "v"):
            raw = int(rec[k][2:6] + rec[k][7:11], 16)
            row[k] = raw - (1 << 32) if raw >= 1 << 31 else raw
        rows.append(row)
    return rows


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--track", required=True, help=".ktrk.json file")
    ap.add_argument("--scenario", default="lap", choices=("lap", "wall"))
    ap.add_argument("--ticks", type=int, default=600)
    ap.add_argument("--npcs", type=int, default=2)
    args = ap.parse_args(argv)
    sys.stdout.write(run(ktrk.loads(Path(args.track).read_text()), args.scenario, args.ticks, args.npcs))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
