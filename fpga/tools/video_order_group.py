"""Which planes may the board composite line-major (cycles/bplanes.h)? The state question.

tools/video_order.py rebuilds the state every pass of a recorded frame consumes in another
order; here the order is the board's: the clear (G, BG) and frame() exactly as the machine runs
them, then the planes in order, where each run of planes given as a GROUP is LATCHed together and
composited a line at a time (each plane's handler, if any, right before its own pass of the
line), and every other plane plane-major. The rebuild is replayed through the RTL compositor
(plane-major passes, each fed its rebuilt state) and must match the machine where the order is
exact.

    uv run python tools/video_order_group.py union_intro 1300         # the board's rule
    uv run python tools/video_order_group.py union_intro 1300--all    # every plane in one group

The board's rule: a group is a run of consecutive enabled planes with no HBL handler. Their
passes see no write in either order, so the rebuild equals the machine by construction; `--all`
(the rule ignored) interleaves handler planes, which changes a frame where one handler writes
what another plane's pass reads (RESOLUTION, RES_FLICKER, palettes): the break test's catch.
"""

from __future__ import annotations

import sys
from pathlib import Path

import video_order as vo
import video_rtl


def rule_groups(s: vo.Split) -> list[list[int]]:
    """Runs of consecutive handler-free planes (pass numbers), as cycles/bplanes.c forms them."""
    handler = {k for (k, _) in s.h}
    groups, run = [], []
    for k in s.planes:
        if k in handler:
            groups += [run] if run else []
            run = []
        else:
            run.append(k)
    return groups + ([run] if run else [])


def _emit_group(w: vo.Writer, s: vo.Split, group: list[int]) -> None:
    for k in group:
        w.emit(vo.START, k, 0)  # every plane of the group LATCHed before its line 0
    handlers = any((k, y) in s.h for k in group for y in range(vo.LINES))
    for y in range(vo.LINES):
        for k in group:
            if not handlers:
                continue  # nothing runs between the passes: nothing to record
            w.emit(vo.PRE, k, y)
            w.apply(s.h.get((k, y), {}))
            w.emit(vo.POST, k, y)
    for k in group:
        w.emit(vo.END, k, 0)


def _emit_plane(w: vo.Writer, s: vo.Split, k: int) -> None:
    w.emit(vo.START, k, 0)
    for y in range(vo.LINES):
        if (k, y) in s.h:
            w.emit(vo.PRE, k, y)
            w.apply(s.h[(k, y)])
            w.emit(vo.POST, k, y)
    w.emit(vo.END, k, 0)


def grouped(s: vo.Split, groups: list[list[int]]) -> bytes:
    """The clear and frame() as plane_major() records them, then the planes, the groups line-major."""
    w = vo.Writer()
    w.apply(s.init)
    w.emit(vo.START, 0, 0)
    for y in range(vo.LINES):
        w.apply(s.wb.get(y - 1, {}))
        w.emit(vo.PRE, 0, y)
        w.apply(s.g.get(y, {}))
        w.emit(vo.POST, 0, y)
    w.apply(s.wb.get(vo.LINES - 1, {}))
    w.emit(vo.END, 0, 0)
    w.apply(s.frame)
    first_of = {g[0]: g for g in groups}
    in_group = {k for g in groups for k in g}
    for k in s.planes:
        if k in first_of:
            _emit_group(w, s, first_of[k])
        elif k not in in_group:
            _emit_plane(w, s, k)
    return bytes(w.out)


def analyse(frames_dir: Path, frame: int, exe: Path, every: bool = False) -> tuple[bool, str]:
    """(matched, the replay's verdict line) for the rule's groups, or one group of every plane."""
    s = vo.split(frames_dir, frame)
    groups = [list(s.planes)] if every else rule_groups(s)
    d = vo.rebuild(frames_dir, frame, grouped(s, groups), "all" if every else "rule")
    r = video_rtl.replay(exe, d, [frame])
    last = (r.stdout.strip().splitlines() or ["(no output)"])[-1]
    return r.returncode == 0 and "-> MATCH" in last, f"groups {groups}: {last.split(': ', 1)[-1]}"


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit("usage: video_order_group.py <cart tag> <frame> [--all] [<frames dir>]")
    tag, f, every = sys.argv[1], int(sys.argv[2]), "--all" in sys.argv
    rest = [a for a in sys.argv[3:] if a != "--all"]
    d = Path(rest[0]) if rest else video_rtl.FPGA / "build" / "vdump" / tag / "frames"
    print(tag, f, analyse(d, f, video_rtl.build_tb(), every)[1])
