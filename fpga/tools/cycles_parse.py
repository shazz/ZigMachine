"""Parse one cycles-sim UART log (fpga/cycles/main.c) into per-frame figures.

The lines, all space-separated integers after the tag:
  ZM CAL 1000 <owner>*5     the probe calibration: 1000 empty CAL_IN spans in CAL_OUT
  ZM FCAL <sum> <n>         float build: counter-read cost, summed over n reads
  ZM BOOT <cycles>          instantiation + boot + skipBoot, one-off
  ZM F <frame> <owner>*5 [<calls> <cycles>]*19   one frame; float fields in the float build
  {json}                    scene_hash.mjs's JSON for the sampled frames
  ZM FL <op> <owner> <calls> <cycles>   float build: whole-run totals per routine
  ZM MIS <loads> <stores>   misaligned accesses the trap handler emulated
  ZM TRAP ... / ZM WASMTRAP ...         fatal
  ZM END <rc>
An <owner> is 8 fields: the 6 counters (soc/zm_cycles.py COUNTERS), the spans
entered into it (n_in) and the spans entered from it (n_out), for the owners
CART, MACH, BLIT, CAL_OUT, CAL_IN in that order (cycles/prof.h).
"""

from __future__ import annotations

import json
from dataclasses import dataclass, field
from pathlib import Path

COUNTERS = ["cycles", "ibus_ack", "ibus_wait", "dbus_rd", "dbus_wr", "dbus_wait"]
OWNERS = ["cart", "mach", "blit", "cal_out", "cal_in"]
# cycles/fcount.c FCLASSES, in order.
CLASSES = "FADD FMUL FDIV FSQRT FCMP FCVT FROUND FNEG F64INT FD DADD DMUL DDIV DSQRT DCMP DCVT DROUND DNEG D64INT"
CLASSES_L = CLASSES.split()
OWNER_FIELDS = len(COUNTERS) + 2

Vec = list[float]


@dataclass
class Run:
    """One (cart, variant) run, with the probe's own cost already subtracted."""

    frames: list[dict[str, Vec]] = field(default_factory=list)  # owner -> counters, per frame
    fclass: list[dict[str, tuple[int, float]]] = field(default_factory=list)  # class -> (calls, cycles)
    fops: dict[tuple[str, str], tuple[int, int]] = field(default_factory=dict)  # (op, owner) -> totals
    json: dict | None = None
    boot: int = 0
    end: int | None = None
    misaligned: tuple[int, int] = (0, 0)
    fatal: str = ""


def _owners(nums: list[int]) -> dict[str, list[int]]:
    return {o: nums[i * OWNER_FIELDS : (i + 1) * OWNER_FIELDS] for i, o in enumerate(OWNERS)}


def _probe(cal: dict[str, list[int]]) -> tuple[Vec, Vec]:
    """Per-span probe cost charged to the owner inside the span, and to the one outside."""
    spans = cal["cal_in"][len(COUNTERS)]
    inner = [c / spans for c in cal["cal_in"][: len(COUNTERS)]]
    outer = [c / spans for c in cal["cal_out"][: len(COUNTERS)]]
    return inner, outer


def _correct(raw: list[int], inner: Vec, outer: Vec) -> Vec:
    n_in, n_out = raw[len(COUNTERS)], raw[len(COUNTERS) + 1]
    return [max(0.0, r - n_in * i - n_out * o) for r, i, o in zip(raw, inner, outer, strict=False)]


def _frame(run: Run, nums: list[int], inner: Vec, outer: Vec, fcal: float) -> None:
    owners = _owners(nums[1 : 1 + len(OWNERS) * OWNER_FIELDS])
    run.frames.append({o: _correct(owners[o], inner, outer) for o in ("cart", "mach", "blit")})
    fl = nums[1 + len(OWNERS) * OWNER_FIELDS :]
    if len(fl) == 2 * len(CLASSES_L):
        run.fclass.append({c: (fl[2 * i], max(0.0, fl[2 * i + 1] - fl[2 * i] * fcal)) for i, c in enumerate(CLASSES_L)})


def parse(path: Path) -> Run:
    run, inner, outer, fcal = Run(), [0.0] * 6, [0.0] * 6, 0.0
    for line in path.read_text(errors="replace").splitlines():
        if line.startswith("{"):
            run.json = json.loads(line)
            continue
        if not line.startswith("ZM "):
            continue
        tag, rest = line[3:].split(" ", 1) if " " in line[3:] else (line[3:], "")
        if tag in ("TRAP", "WASMTRAP"):
            run.fatal = line
        elif tag == "FL":
            op, owner, calls, cyc = rest.split()
            run.fops[(op, OWNERS[int(owner) - 1] if int(owner) else "idle")] = (int(calls), int(cyc))
        elif tag in ("CAL", "FCAL", "BOOT", "F", "MIS", "END"):
            nums = [int(x) for x in rest.split()]
            if tag == "CAL":
                inner, outer = _probe(_owners(nums[1:]))
            elif tag == "FCAL":
                fcal = nums[0] / nums[1]
            elif tag == "F":
                _frame(run, nums, inner, outer, fcal)
            elif tag == "BOOT":
                run.boot = nums[0]
            elif tag == "MIS":
                run.misaligned = (nums[0], nums[1])
            else:
                run.end = nums[0]
    return run
