"""Read the video integration sim's logs (tools/video_sim_run.py) and say what
they show: whether each run's PFB hashes equal apps/scene_hash.mjs's and the
native host's, whether the scanout ever underran, and what a frame costs.

    uv run python tools/video_sim_report.py      # re-read build/vcycles/uart, rewrite the report

A frame's figures (Mc = millions of 160 MHz sys cycles, steady frames only):
  cart    frame() and the HBL handlers;  seq  the sequencer issuing and waiting
          for passes, minus the wait for the swap;  cpu max  their sum, worst frame
  wall    the frame from its first pass to PRESENT, swap wait included
  comp    COMPOSITOR clocks (comp domain) a pass was running;  dma  cycles a DMA burst was
  MB/f    main-RAM bytes a frame: the CPU's, and the compositor's DMA (the
          scanout's 112,000 beats a VBL taken out)
  MB/s    both at 60 frames a second, plus the scanout's 53.8 MB/s
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass, field
from pathlib import Path
from statistics import mean

FPGA = Path(__file__).resolve().parent.parent
VCYC = FPGA / "build/vcycles"
REF = FPGA / "build/cycles/ref"
WARMUP = 5
SCAN_BEATS, VBL_CYCLES = 112_000, 160e6 * 1056 * 628 / 40e6  # sys cycles a 60 Hz frame (4:1)
HASHING = 1_000_000  # idle cycles: the frame was hashed (the scanout runs on meanwhile)
VF = ["cart", "seq", "blit", "idle", "swap", "comp", "dma", "cpu_rd", "cpu_wr", "dma_rd", "dma_wr", "both"]


@dataclass
class Run:
    frames: list[dict[str, int]] = field(default_factory=list)
    json: dict[str, object] | None = None
    vstat: list[int] = field(default_factory=list)
    end: int | None = None
    trap: str = ""


def parse(text: str) -> Run:
    run = Run()
    for line in text.splitlines():
        if line.startswith("ZM VF "):
            nums = [int(x) for x in line.split()[3:]]
            run.frames.append(dict(zip(VF, nums, strict=True)))
        elif line.startswith("{"):
            run.json = json.loads(line)
        elif line.startswith("ZM VSTAT "):
            run.vstat = [int(x) for x in line.split()[2:]]
        elif line.startswith("ZM END "):
            run.end = int(line.split()[2])
        elif re.match(r"ZM (TRAP|WASMTRAP)", line):
            run.trap = line
    return run


def verdict(tag: str, run: Run) -> str:
    """'ok' only if it ran to the end, the scanout never underran, and the hashes
    equal both references for the same frames."""
    if run.trap or run.end != 0 or run.json is None:
        return f"FAIL {run.trap or f'end {run.end}'}"
    if not run.vstat or run.vstat[0] or run.vstat[1]:
        return f"FAIL underrun/overflow {run.vstat}"
    j = run.json
    for kind in ("js", "native"):
        ref = REF / f"{tag}.{j['frames']}.{j['every']}.{kind}.json"
        if not ref.exists():
            return f"no-{kind}"
        r = json.loads(ref.read_text())
        if (r["samples"], r["total"]) != (j["samples"], j["total"]):
            return f"MISMATCH-{kind}"
    return "ok"


def figures(run: Run) -> dict[str, float]:
    fs = run.frames[WARMUP:] if len(run.frames) > WARMUP else run.frames
    fs = [f for f in fs if f["idle"] < HASHING] or fs  # a sampled frame waits for its untimed hash
    if not fs:
        return {}
    wall = [f["cart"] + f["seq"] + f["blit"] + f["idle"] for f in fs]
    # The scanout reads a picture (112,000 beats) every VBL, however long the frame.
    scan = [SCAN_BEATS * w / VBL_CYCLES for w in wall]
    comp_dma = [(f["dma_rd"] + f["dma_wr"] - sc) * 8 for f, sc in zip(fs, scan, strict=True)]
    cpu_bytes = [(f["cpu_rd"] + f["cpu_wr"]) * 4 for f in fs]
    return {
        "cart": mean(f["cart"] for f in fs),
        "seq": mean(f["seq"] - f["swap"] for f in fs),
        "cpu_max": max(f["cart"] + f["seq"] - f["swap"] for f in fs),
        "wall": mean(wall),
        "comp": mean(f["comp"] for f in fs),
        "dma": mean(f["dma"] for f in fs),
        "cpu_mb": mean(cpu_bytes) / 1e6,
        "comp_mb": mean(comp_dma) / 1e6,
        # At 60 frames a second: the CPU's and the compositor's bytes a frame, plus the scanout.
        "mbs": (mean(cpu_bytes) + mean(comp_dma)) * 60 / 1e6 + SCAN_BEATS * 8 * 60 / 1e6,
    }


def table(runs: dict[str, Run]) -> list[str]:
    head = "| run | verdict | swaps | cart | seq | cpu max | wall | comp | dma | CPU MB/f | comp MB/f | MB/s @60 |"
    lines = [head, "|" + "---|" * 12]
    for key, run in sorted(runs.items()):
        f, tag = figures(run), key.split("/")[-1]
        v = verdict(tag, run)
        if not f:
            lines.append(f"| {key} | {v} |" + " |" * 10)
            continue
        swaps = run.vstat[2] if len(run.vstat) > 2 else 0
        mc = " | ".join(f"{f[k] / 1e6:.2f}" for k in ("cart", "seq", "cpu_max", "wall", "comp", "dma"))
        mb = f"{f['cpu_mb']:.2f} | {f['comp_mb']:.2f} | {f['mbs']:.0f}"
        lines.append(f"| {key} | {v} | {swaps} | {mc} | {mb} |")
    return lines


def load() -> dict[str, Run]:
    """build/vcycles/uart/<mem>/<variant>/<tag>.txt -> '<mem>/<variant>/<tag>'."""
    out = {}
    for p in sorted((VCYC / "uart").glob("*/*/*.txt")):
        out["/".join(p.with_suffix("").parts[-3:])] = parse(p.read_text(errors="replace"))
    return out


def main() -> None:
    runs = load()
    text = "\n".join(table(runs)) + "\n"
    (VCYC / "report.txt").write_text(text)
    print(text, end="")


if __name__ == "__main__":
    main()
