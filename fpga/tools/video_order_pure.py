"""The gate for pure HBL handlers (memmap REG_FB_HBL_PURE, 1.8.0; cycles/vseq_group.c).

A cart that flags a plane's handler pure lets the board composite that plane line by line with its
neighbours, the handler run right before its own pass of the line and RES_FLICKER stored as the
plane's own handler left it. This replays named carts' frames in exactly that order (the board's
rule: runs of planes with no handler or a pure one, no medium plane beside a handler) through the
RTL compositor (tools/video_order_group.py --fw) and fails unless every frame equals the machine,
and unless at least one frame really groups a handler plane with another plane (a cart that lost
its flag would pass by testing nothing).

    uv run python tools/video_order_pure.py replicants union_intro@3000 ...   [--frames 300,600]
    uv run python tools/video_order_pure.py --break [carts]   # also: the synthetic overscan frames
                                                              # grouped with no RES_FLICKER store must DIFFER

The replay sees the region (registers, palettes, BEAM): a handler that talks to another through
cart RAM is beyond it, which is why only handlers ZigOS documents as pure may carry the flag.
"""

from __future__ import annotations

import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

FPGA = Path(__file__).resolve().parent.parent
# A clean tree has no gen/ (the gate's fresh worktree): the memmap the tools import, made first.
if not (FPGA / "gen" / "memmap.py").exists():
    subprocess.run(["make", "-s", "-C", str(FPGA), "memmap"], check=True, capture_output=True)

import video_dump  # noqa: E402  (after gen/ exists)
import video_order as vo  # noqa: E402
import video_order_group as vog  # noqa: E402
import video_rtl  # noqa: E402

mm = vo.vc.mm


def _ensure_tools() -> None:
    """A worktree has no fpga/.tools (wabt for the native host): borrow the main checkout's."""
    here = FPGA / ".tools"
    if here.exists():
        return
    common = Path(os.popen(f"git -C {FPGA} rev-parse --path-format=absolute --git-common-dir").read().strip())
    main = common.parent / "fpga" / ".tools"
    if main.is_dir():
        here.symlink_to(main)


def _state(s: vo.Split) -> dict[int, int]:
    """The register words when the plane phase starts: init, the clear's writes, frame()'s."""
    st = dict(s.init)
    for y in range(vo.LINES):
        st.update(s.wb.get(y - 1, {}))
        st.update(s.g.get(y, {}))
    st.update(s.wb.get(vo.LINES - 1, {}))
    st.update(s.frame)
    return st


def _byte(st: dict[int, int], off: int) -> int:
    return (st.get(off // 4, 0) >> (8 * (off % 4))) & 0xFF


def board_groups(s: vo.Split) -> tuple[list[list[int]], bool]:
    """cycles/bplanes.c's runs (pass numbers) with pure handlers in them, and whether one of them
    holds a handler plane beside another plane (what this gate is about)."""
    st = _state(s)

    def handler(k: int) -> bool:
        return _byte(st, mm.REG_FB_HBL_ID + 2 * (k - 1)) | _byte(st, mm.REG_FB_HBL_ID + 2 * (k - 1) + 1) != 0

    def pure(k: int) -> bool:
        return not handler(k) or _byte(st, mm.REG_FB_HBL_PURE + k - 1) != 0

    groups, run = [], []
    for k in s.planes + [0]:  # 0: the end
        if k and pure(k):
            run.append(k)
            continue
        medium = any(_byte(st, mm.REG_FB_MODE + k2 - 1) == mm.FB_MODE_MEDIUM for k2 in run)
        if run and not (medium and any(handler(k2) for k2 in run)):
            groups.append(run)
        run = []
    mixed = any(len(g) > 1 and any(handler(k) for k in g) for g in groups)
    return groups, mixed


def check(tag: str, frames: list[int], exe: Path) -> tuple[bool, list[str]]:
    """(passed, report lines) for one cart; its native host is built already (main)."""
    d = video_dump.dump(tag, frames)
    ok, mixed, out = True, False, []
    for f in frames:
        s = vo.split(d, f)
        groups, m = board_groups(s)
        mixed |= m
        rec = vo.rebuild(d, f, vog.grouped(s, groups, fw=True), "pure")
        r = video_rtl.replay(exe, rec, [f])
        last = (r.stdout.strip().splitlines() or ["(no output)"])[-1]
        good = r.returncode == 0 and "-> MATCH" in last
        ok &= good
        out.append(f"{tag} {f} groups {groups}: {'MATCH' if good else 'DIFFER ' + last}")
    if not mixed:
        out.append(f"{tag}: no frame groups a pure handler plane with another plane: nothing was tested")
    return ok and mixed, out


def broken(exe: Path) -> bool:
    """The synthetic overscan frames (planes flickering on different lines) in one group with
    the RES_FLICKER store left out: True when the replay notices."""
    d = video_dump.synth("overscan")
    s = vo.split(d, 1)
    rec = vo.rebuild(d, 1, vog.grouped(s, [list(s.planes)], fw=False), "pure_break")
    r = video_rtl.replay(exe, rec, [1])
    return r.returncode != 0


def main(args: list[str]) -> int:
    _ensure_tools()
    frames = [300, 600]
    if "--frames" in args:
        at = args.index("--frames")
        frames, args = [int(x) for x in args[at + 1].split(",")], args[:at] + args[at + 2 :]
    video_dump.memmap_header()
    exe = video_rtl.build_tb()
    want_break = "--break" in args
    args = [a for a in args if a != "--break"]
    if not args and not want_break:
        sys.exit(__doc__)
    # The native hosts of today's docs/demo-<tag>.wasm, one make at a time (they share
    # build/host/common); then the carts' dumps and replays side by side.
    # cart@f1,f2: that cart's own frames (a screen that only starts later, union_intro's main).
    picks = [(a.split("@")[0], [int(x) for x in a.split("@")[1].split(",")] if "@" in a else frames) for a in args]
    for t, _ in picks:
        subprocess.run(["make", "-s", "-j4", "-C", str(FPGA), "host", f"CART={t}"], check=True, capture_output=True)
    with ThreadPoolExecutor(max_workers=4) as pool:
        results = list(pool.map(lambda tf: (tf[0], *check(tf[0], tf[1], exe)), picks))
    for _, _, lines in results:
        print("\n".join(lines))
    bad = [t for t, good, _ in results if not good]
    if args:
        print("pure HBL groups:", "all MATCH" if not bad else f"FAIL {' '.join(bad)}")
    if want_break:  # after the carts: the synthetic frames need build/host/common, built above
        caught = broken(exe)
        print("break: no RES_FLICKER store", "caught" if caught else "NOT CAUGHT")
        bad += [] if caught else ["--break"]
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
