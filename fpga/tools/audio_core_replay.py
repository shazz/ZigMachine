"""Replay the MACHINE's register writes (host_audio's log) into the audio core on its
own (tests/tb/audio_core_tb.cpp at the board's 100 MHz rates, the `core100` bench of
tests/test_rtl_audio.py), on the board SoC sim's timeline, and compare that with what
the core made inside the SoC (the tap), sample for sample.

    uv run python tools/audio_core_replay.py build/hcycles/audio/tutorial

The writes before the song are the boot's (no machine time): they go where the SoC
applied them. Every song write goes at the song's start in the SoC plus its sample in
the machine's stream. If the two streams are equal, the SoC (window, queue, stamps,
HP3) added nothing: what the core plays is exactly the machine's writes at the
machine's samples. (jt49's sound depends on its whole history since reset, so the
replay keeps the SoC's reset-to-song timeline; tools/audio_sim_compare.py compares
the sound with the machine's own chips.)
"""

import argparse
import subprocess
import sys
from pathlib import Path

import audio_sim_compare as cmp

FPGA = Path(__file__).resolve().parent.parent
FIELDS = {4: "step", 5: "vol", 6: "pan", 7: "pos"}


def command(addr: int, data: int) -> str:
    """One write as an audio_script.h line (tests/tb/audio_script.h)."""
    if addr < 0x40:
        return f"ym {addr // 4} {data}"
    if addr == 0x40:
        return "reset"
    ch, f = (addr - 0x100) // 0x40, (addr % 0x40) // 4
    if f in FIELDS:
        value = data - 512 if f == 6 and data & 0x100 else data
        return f"{FIELDS[f]} {ch} {value}"
    if f == 8 and data in (0, 1):
        return f"act {ch} {data}"
    raise SystemExit(f"audio_core_replay: write {addr:03x}={data:x} has no script form (a PCM trigger)")


def script(writes: list[cmp.Write], samples: int) -> str:
    """The writes, in order, with the runs between them, up to `samples`."""
    lines, t = [], 0
    for ts, addr, data in writes:
        if ts >= samples:
            break
        if ts > t:
            lines.append(f"run {ts - t}")
            t = ts
        lines.append(command(addr, data))
    lines.append(f"run {samples - t}")
    return "\n".join(lines) + "\n"


def bench() -> Path:
    sys.path.insert(0, str(FPGA / "tests"))
    import test_rtl_audio  # after the path insert: its bench builder

    exe = test_rtl_audio.BUILD / "core100_tb"
    return exe if exe.exists() else test_rtl_audio.build_bench("core100")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("run", type=Path, help="tools/audio_sim_run.py's output directory")
    a = ap.parse_args()
    nw, (n0, nk), _ = cmp.parse_log((a.run / "native.w").read_text(), "L ")
    _, (b0, bk), _ = cmp.parse_log((a.run / "uart.txt").read_text(errors="replace"), "ZM SONG ")
    bw, _, tap = cmp.parse_log((a.run / "audio_tap.txt").read_text(), "-")
    if nk != bk:
        raise SystemExit(f"audio_core_replay: {nk} boot writes by the machine, {bk} on the board")
    span = min(len(tap) - b0, (a.run / "native.pcm").stat().st_size // 4 - n0)
    timeline = [(bw[i][0], w[1], w[2]) for i, w in enumerate(nw[:nk])]
    timeline += [(b0 + ts - n0, addr, data) for ts, addr, data in nw[nk:]]
    (a.run / "replay.txt").write_text(script(timeline, b0 + span))
    out = a.run / "replay.raw"
    subprocess.run([str(bench()), str(a.run / "replay.txt"), "/dev/null", "dump", str(out)], capture_output=True)
    ok, report = cmp.stream_cmp(tap[: b0 + span], out.read_bytes(), "exact", a.run)
    print(f"the SoC's core vs the core fed the machine's writes on the same timeline:\n{report}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
