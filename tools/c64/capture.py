"""capture.py <prg> <outdir> <frame> [<frame> ...]

The clock is the raster: frame N = the Nth time the beam reaches line 288 (the first line
after the 384x272 capture window, rows = lines 16..287) after the intro's start (C64_ENTRY,
default $1E00: 1988).
For each requested N:
  <outdir>/f<N>.png      VICE screenshot of frame N, taken at line 300 (at 288 VICE's canvas
                         still shows the previous frame's lines 248-250),
  <outdir>/f<N>.ram      64 KB RAM at line 288 of frame N-1 (window start; line 300 when N-1
                         was captured too: nothing the VIC shows changes in between),
  <outdir>/f<N>.vic      $D000-$D02E at the window start,
  <outdir>/f<N>.cia      $DD00 (VIC bank) at the window start,
  <outdir>/f<N>.col      colour RAM ($D800-$DBFF) at the window start,
  <outdir>/f<N>.trace    every VIC + sprite-pointer store inside the window:
                         "line cycle addr value".
Frames must be ascending.
"""
import os
import re
import sys

sys.path.insert(0, __file__.rsplit("/", 1)[0])
from vicemon import Vice  # noqa: E402

# C64_ENTRY (hex, default 1E00: 1988) is the first break; C64_TRACE adds store ranges ("a b,a b").
TRACE = ("d000 d02e", "07f8 07ff", "f3f8 f3ff") + tuple(
    r for r in os.environ.get("C64_TRACE", "").split(",") if r)
ENTRY = int(os.environ.get("C64_ENTRY", "1E00"), 16)
STOP = re.compile(r"#(\d+) \(Stop on\s+exec ([0-9a-f]{4})\)\s+(\d+)/")
TRC = re.compile(r"#\d+ \(Trace\s+store ([0-9a-f]{4})\)\s+(\d+)/\$[0-9a-f]+,\s+(\d+)/")
REG = re.compile(r"A:([0-9A-F]{2}) X:([0-9A-F]{2}) Y:([0-9A-F]{2})")


def store_value(nxt: str) -> str:
    """Value of a traced store from the instruction line VICE prints after it."""
    r = REG.search(nxt)
    if not r:
        return "??"
    op = nxt[9:11]
    a, x, y = r.group(1), r.group(2), r.group(3)
    return {"8D": a, "9D": a, "99": a, "85": a, "95": a, "8E": x, "86": x, "8C": y, "84": y,
            "8F": f"{int(a, 16) & int(x, 16):02X}"}.get(op, "RMW")


class Capture:
    def __init__(self, prg: str, out: str) -> None:
        self.v = Vice(prg, ENTRY)
        self.v.cmd("delete")  # -initbreak leaves its checkpoint: an IRQ entry would stop every frame
        self.out = out
        self.frames = 0
        self.end_bp = self._bp("break 0000 ffff if rl == $120")
        self.mid_bp = self._bp("break 0000 ffff if rl == $a")
        self.v.cmd(f"disable {self.mid_bp}")

    def _bp(self, c: str) -> int:
        return int(re.search(r"(?:BREAK|TRACE|WATCH): (\d+)", self.v.cmd(c)).group(1))

    def to_frame(self, n: int) -> str:
        """Run to line 288 of frame n (invariant: parked on line 288 of self.frames, or
        before the first frame when self.frames == 0)."""
        log = ""
        while self.frames < n:
            if self.frames:
                self._swap(self.end_bp, self.mid_bp)
                log += self.v.cmd("x")  # off line 288: line 10 of the next frame
                self._swap(self.mid_bp, self.end_bp)
            log += self.v.cmd("x")  # line 288
            self.frames += 1
        return log

    def _swap(self, off: int, on: int) -> None:
        self.v.cmd(f"disable {off}")
        self.v.cmd(f"enable {on}")

    def snapshot(self, path: str) -> None:
        self.v.cmd("bank ram")
        self.v.cmd(f'bsave "{path}.ram" 0 0000 ffff')
        self.v.cmd("bank io")
        self.v.cmd(f'bsave "{path}.vic" 0 d000 d02e')
        self.v.cmd(f'bsave "{path}.cia" 0 dd00 dd00')
        self.v.cmd(f'bsave "{path}.col" 0 d800 dbff')
        self.v.cmd("bank cpu")

    def frame(self, n: int) -> None:
        if n <= self.frames:
            raise ValueError("frames must be ascending")
        base = os.path.abspath(os.path.join(self.out, f"f{n}"))
        self.to_frame(n - 1)
        self.snapshot(base)
        ids = [self._bp(f"trace store {r}") for r in TRACE]
        out = self.to_frame(n)
        for i in ids:
            self.v.cmd(f"delete {i}")
        # VICE's canvas still holds the last frame's lines 248-250 at line 288 (seen on
        # Transmission64's part 1): shoot at line 300, where every visible line is this frame's
        self.v.cmd(f"disable {self.end_bp}")
        late = self._bp("break 0000 ffff if rl == $12c")
        self.v.cmd("x")
        self.v.cmd(f"delete {late}")
        self.v.cmd(f"enable {self.end_bp}")
        self.v.cmd(f'screenshot "{base}.png" 2')
        lines = out.splitlines()
        with open(base + ".trace", "w") as t:
            for i, ln in enumerate(lines):
                m = TRC.match(ln)
                if m:
                    nxt = lines[i + 1] if i + 1 < len(lines) else ""
                    t.write(f"{m.group(2)} {m.group(3)} {m.group(1)} {store_value(nxt)}\n")


def main() -> None:
    prg, out = sys.argv[1], sys.argv[2]
    os.makedirs(out, exist_ok=True)
    c = Capture(prg, out)
    for n in sorted(int(a) for a in sys.argv[3:]):
        c.frame(n)
        print("frame", n, flush=True)
    c.v.close()


if __name__ == "__main__":
    main()
