"""Which carts' music fits on BARD: every song every cart asks for, and an estimate of its load.

    uv run python tools/bard_load_survey.py [--frames 1500] [--json out.json] [--only <song>...]

BARD (the sound CPU, docs/FPGA_SOUND_CPU.md) has 1.67 Mc a 60 Hz frame. An SNDH on Musashi costs
two things there: the 68000 code itself, and a fixed glue per interrupt (the render block that is
split at it, the MFP bookkeeping, m68k_execute's entry and exit). A digidrum tune's timer runs at
several kHz, so the glue dominates: that is what put Wow Scroller (Timer A 7,585 Hz) at 125 % on
the board and Monty (Timer D 10,593 Hz) at about 200 %.

So each subtune is run on Musashi in the counting oracle (`make sndh-survey`): per frame, the
calls into the tune (play and every interrupt) and the 68000 instructions. `estimate()` turns both
into BARD Mc with constants fitted to snd-bench's measured points. The x86 time is no measure: on
a loaded box it moved 3x between two runs of the same tune. The table gives the mean and the worst
half second: a load held longer than BARD's few frames of lead plays slow. A song whose native
driver (status > 4) recognises it plays at its own measured cost instead.

The songs: every song-named literal in docs/demo-*.wasm (as tools/song_pack.py finds them), plus
SOURCE_ONLY, the carts whose literal the linker packed out of reach of that scan.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
from pathlib import Path

from song_pack import NAME

FPGA = Path(__file__).resolve().parent.parent
ROOT = FPGA.parent
MUSIC = ROOT / "docs/music"
ORACLE = FPGA / "build/host/oracle/sndh_survey"  # make sndh-survey
# Carts whose song name the wasm scan does not see (built from a packed data segment): their sources'.
SOURCE_ONLY = {
    "tutorial": ["sos.sndh"], "tutorial_steps": ["sos.sndh"], "leonard": ["sos.sndh"],
    "replicants_dd2": ["sos.sndh"], "vex": ["vex.sndh"], "c-tutorial": ["sos.sndh"],
    "c-tutorial_steps": ["sos.sndh"], "c-screen34": ["sos.sndh"], "c-fujiboink": ["fujiboink_thud.sndh"],
    "rust-tutorial": ["sos.sndh"], "rust-tutorial_steps": ["sos.sndh"],
}
# The fit (docs/FPGA_SOUND_CPU.md "Every cart's music"): Mc a 60 Hz frame on BARD (I16w2D4, 100 MHz,
# soc_hp_snd), from snd-bench on Musashi: sos.sndh 0.19-0.29 (0.8 calls, 294 instructions a frame),
# Wow Scroller 2.65-2.69 (127 calls, 2,033), Monty 3.35-3.86 (177 calls, 3,166). The call is what
# costs: ~17.8 k cycles of glue around it, against ~100 a 68000 instruction.
BASE_MC = 0.20
CALL_MC = 0.0178
INSN_MC = 0.0001
BUDGET_MC = 1.67
WINDOW = 30  # frames (0.5 s): a load sustained longer than BARD's 3-4 frames of lead slows the music


def cart_songs() -> dict[str, list[str]]:
    out: dict[str, list[str]] = {}
    for w in sorted((ROOT / "docs").glob("demo-*.wasm")):
        cart = w.stem.removeprefix("demo-")
        names = {m.group().decode() for m in NAME.finditer(w.read_bytes())} | set(SOURCE_ONLY.get(cart, []))
        names = {n for n in names if (MUSIC / n).is_file()}
        if names:
            out[cart] = sorted(names)
    return out


def header(song: str) -> str:
    """The SNDH's play timer and rate (TA/TB/TC/TD/!V tags); "ICE" for a packed file."""
    data = (MUSIC / song).read_bytes()[:4096]
    if data[12:16] != b"SNDH":
        return "ICE" if data[:4] == b"ICE!" else "?"
    end = data.find(b"HDNS")
    m = re.search(rb"(TA|TB|TC|TD|!V)(\d+)", data[: end if end > 0 else len(data)])
    return f"{m.group(1).decode()}{int(m.group(2))}" if m else "VBL50"


def run(song: str, tune: int, frames: int, musashi: bool = True) -> str:
    env = dict(os.environ, ZM_SNDH_TIMERS="1", ZM_AUDIO_DIGEST="/dev/null")
    if musashi:
        env["ZM_SNDH_MUSASHI"] = "1"
    return subprocess.run([str(ORACLE), song, str(tune), str(frames)], env=env, capture_output=True, text=True,
                          check=True).stdout


def estimate(calls: float, insns: float) -> float:
    """BARD Mc a frame for a tune on Musashi, from its calls and 68000 instructions a frame."""
    return BASE_MC + calls * CALL_MC + insns * INSN_MC


def loads(out: str) -> tuple[float, float, float]:
    """Mean and sustained-peak (the worst WINDOW frames) Mc a frame, and the peak timer rate (Hz)."""
    per = [estimate(int(c), int(i)) for _, _, _, i, c in (ln.split() for ln in out.splitlines()
                                                         if ln.startswith("ZM COUNT"))]
    rates = [sum(map(int, ln.split()[3:])) for ln in out.splitlines() if ln.startswith("ZM TIMERS")]
    win = [sum(per[k : k + WINDOW]) / WINDOW for k in range(max(1, len(per) - WINDOW + 1))]
    return sum(per) / max(1, len(per)), max(win), float(max(rates, default=0))


def survey_song(song: str, frames: int) -> list[dict[str, object]]:
    n = int(re.search(r"subtunes (\d+)", run(song, 0, 1)).group(1))  # type: ignore[union-attr]  # [always printed]
    rows: list[dict[str, object]] = []
    for tune in range(1, max(1, n) + 1):
        mean, peak, hz = loads(run(song, tune, frames))
        status = int(re.search(r"native (\d+)", run(song, tune, 1, musashi=False)).group(1))  # type: ignore[union-attr]
        rows.append({"song": song, "tune": tune, "of": n, "timer": header(song), "mfp_hz": hz,
                     "mean_pct": round(100 * mean / BUDGET_MC), "peak_pct": round(100 * peak / BUDGET_MC),
                     "native": status})
    return rows


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--frames", type=int, default=1500)
    ap.add_argument("--json", type=Path)
    ap.add_argument("--only", nargs="*")
    a = ap.parse_args()
    carts = cart_songs()
    songs = sorted({s for v in carts.values() for s in v if s.endswith(".sndh")})
    rows = [r for s in songs if not a.only or s in a.only for r in survey_song(s, a.frames)]
    for r in sorted(rows, key=lambda r: -int(r["peak_pct"])):  # type: ignore[call-overload]  # [ints]
        users = ",".join(c for c, v in carts.items() if r["song"] in v)
        print(f"{r['peak_pct']:4}% {r['mean_pct']:4}%  {r['song']} #{r['tune']}/{r['of']}  {r['timer']}  "
              f"MFP {r['mfp_hz']:.0f} Hz  native {r['native']}  [{users}]")
    if a.json:
        a.json.write_text(json.dumps({"carts": carts, "rows": rows}, indent=1))


if __name__ == "__main__":
    main()
