"""trace_all.py <prg> <out.txt> <frames>: the whole write stream, frame by frame.

Same raster clock as capture.py (frame N ends when the beam reaches line 288 for the Nth
time after $1E00). Writes "F <n>" before frame n's stores (those after line 288 of
frame n-1 up to line 288 of frame n), then "line cycle addr value" per store to the VIC
($D000-$D02E), the sprite pointers of both banks, $DD00 and the part-done flag.
Also dumps the VIC registers and RAM at the $1E00 entry to <out>.vic / <out>.ram."""
import re
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from capture import TRC, store_value  # noqa: E402
from vicemon import Vice  # noqa: E402

TRACE = ("d000 d02e", "07f8 07ff", "f3f8 f3ff", "dd00 dd00", "1ffe 1ffe")
BRK = re.compile(r"(?:BREAK|TRACE): (\d+)")


def main() -> None:
    prg, out, frames = sys.argv[1], sys.argv[2], int(sys.argv[3])
    v = Vice(prg, 0x1E00)
    v.cmd("bank ram")
    v.cmd(f'bsave "{out}.ram" 0 0000 ffff')
    v.cmd("bank io")
    v.cmd(f'bsave "{out}.vic" 0 d000 d02e')
    v.cmd(f'bsave "{out}.cia" 0 dd00 dd00')
    v.cmd("bank cpu")
    end_bp = int(BRK.search(v.cmd("break 0000 ffff if rl == $120")).group(1))
    mid_bp = int(BRK.search(v.cmd("break 0000 ffff if rl == $a")).group(1))
    v.cmd(f"disable {mid_bp}")
    for r in TRACE:
        v.cmd(f"trace store {r}")
    with open(out, "w") as f:
        for n in range(1, frames + 1):
            log = v.cmd("x")  # to line 288 of frame n
            v.cmd(f"disable {end_bp}")
            v.cmd(f"enable {mid_bp}")
            tail = v.cmd("x")  # line 10 of frame n+1: stores in 288..311 belong to frame n+1
            v.cmd(f"disable {mid_bp}")
            v.cmd(f"enable {end_bp}")
            f.write(f"F {n}\n")
            emit(f, log)
            pending = tail
            # stores after 288 are written under the NEXT frame's header
            f.write("#\n")
            emit(f, pending)
    v.close()


def emit(f, log: str) -> None:  # noqa: ANN001
    lines = log.splitlines()
    for i, ln in enumerate(lines):
        m = TRC.match(ln)
        if m:
            nxt = lines[i + 1] if i + 1 < len(lines) else ""
            f.write(f"{m.group(2)} {m.group(3)} {m.group(1)} {store_value(nxt)}\n")


main()
