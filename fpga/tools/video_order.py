"""Would a cart's frame look different if the HBL handlers ran line by line?

The machine renders plane-major: hwClear runs the global HBL handler (G) and the
background (BG) for all 280 lines, then the cart's frame(), then each enabled
plane p runs its handler (Hp) and its pass for all its lines. Hardware composes
line-major, so the CPU would run, at VBL, frame(); then for each line y, G(y),
BG(y), then Hp(y) and plane p's pass for p = 0..3. A handler that writes what
another plane's pass reads (or frame() what a G handler or BG reads) can then
be seen at a different time.

This tool takes a recorded frame (tools/video_dump.py), splits its records into
who wrote what (G, BG's own write-backs, frame(), each Hp), and rebuilds the
state every pass consumes in either order. Both are replayed through the RTL
compositor (tools/video_rtl.py): the plane-major rebuild must match the machine
(the control: it proves the split), and the line-major one counts the pixels,
per pass and in the browser's picture, that would change on hardware.

    uv run python tools/video_order.py union_main 300

Writes are replayed as the values the machine stored. A handler that READS
video state and derives what it writes, or that talks to another through cart
RAM, is beyond what the records show.
"""

import struct
import sys
from dataclasses import dataclass, field
from pathlib import Path

import video_cover as vc
import video_rtl

PRE, POST, START, END = 1, 2, 3, 4
LINES = vc.mm.RASTER_HEIGHT
FRAME_WORD = vc.mm.REG_FRAME // 4
OUT = Path(__file__).resolve().parent.parent / "build" / "vorder"


@dataclass
class Split:
    """One frame's writes, by writer."""

    init: dict[int, int]
    planes: list[int]
    g: dict[int, dict[int, int]] = field(default_factory=dict)  # G(y)
    wb: dict[int, dict[int, int]] = field(default_factory=dict)  # BG(y)'s own write-backs
    frame: dict[int, int] = field(default_factory=dict)  # frame()
    h: dict[tuple[int, int], dict[int, int]] = field(default_factory=dict)  # (pass, y)


def split(frames_dir: Path, frame: int) -> Split:
    recs = vc.records(frames_dir / f"f{frame}.rec")
    mask = int((frames_dir / f"f{frame}.meta").read_text().split()[1])
    s = Split(init=dict(recs[0][3]), planes=[p + 1 for p in range(4) if mask >> p & 1])
    for kind, pas, line, delta in recs[1:]:
        if pas == 0 and kind == PRE and line > 0:
            s.wb[line - 1] = delta
        elif pas == 0 and kind == POST:
            s.g[line] = delta
        elif pas == 0 and kind == END:
            # The last line's write-back and FRAME + 1; without a G handler, a
            # BEAM list can only have been painted (and consumed) on line 0.
            rest = {w: v for w, v in delta.items() if w != FRAME_WORD}
            s.wb.setdefault(LINES - 1, {}).update({w: v for w, v in delta.items() if w == FRAME_WORD})
            s.wb.setdefault(LINES - 1 if s.g else 0, {}).update(rest)
        elif pas > 0 and kind == START:
            s.frame.update(delta)  # only the first plane pass sees a change: frame()'s
        elif pas > 0 and kind == POST:
            s.h[(pas, line)] = delta
    return s


class Writer:
    """Records in tools/video_dump/vdump_rec.c's format, as deltas of full states."""

    def __init__(self) -> None:
        self.state: dict[int, int] = {}
        self.sent: dict[int, int] = {}
        self.out = bytearray()

    def apply(self, delta: dict[int, int]) -> None:
        self.state.update(delta)

    def emit(self, kind: int, pas: int, line: int) -> None:
        delta = {w: v for w, v in self.state.items() if self.sent.get(w, 0) != v}
        self.out += struct.pack("<BBHH", kind, pas, line, len(delta))
        for w, v in sorted(delta.items()):
            self.out += struct.pack("<HI", w, v)
        self.sent = dict(self.state)


def plane_major(s: Split) -> bytes:
    w = Writer()
    w.apply(s.init)
    w.emit(START, 0, 0)
    for y in range(LINES):
        w.apply(s.wb.get(y - 1, {}))
        w.emit(PRE, 0, y)
        w.apply(s.g.get(y, {}))
        w.emit(POST, 0, y)
    w.apply(s.wb.get(LINES - 1, {}))
    w.emit(END, 0, 0)
    w.apply(s.frame)
    for k in s.planes:
        w.emit(START, k, 0)
        for y in range(LINES):
            if (k, y) in s.h:
                w.emit(PRE, k, y)
                w.apply(s.h[(k, y)])
                w.emit(POST, k, y)
        w.emit(END, k, 0)
    return bytes(w.out)


def line_major(s: Split) -> bytes:
    w = Writer()
    w.apply(s.init)
    w.emit(START, 0, 0)
    w.apply(s.frame)  # frame() at VBL, before the first line
    for k in s.planes:
        w.emit(START, k, 0)  # every plane latched before line 0
    for y in range(LINES):
        w.emit(PRE, 0, y)
        w.apply(s.g.get(y, {}))
        w.emit(POST, 0, y)
        w.apply(s.wb.get(y, {}))
        for k in s.planes:
            w.emit(PRE, k, y)
            w.apply(s.h.get((k, y), {}))
            w.emit(POST, k, y)  # every line: other planes' handlers may have run since
    for k in [0, *s.planes]:
        w.emit(END, k, 0)
    return bytes(w.out)


def rebuild(frames_dir: Path, frame: int, rec: bytes, order: str) -> Path:
    tag = frames_dir.parent.name if frames_dir.name == "frames" else frames_dir.name
    d = OUT / tag / order
    d.mkdir(parents=True, exist_ok=True)
    for ext in ("mem", "pfb", "meta"):  # linked: the recording is megabytes and read-only here
        link = d / f"f{frame}.{ext}"
        link.unlink(missing_ok=True)
        link.symlink_to((frames_dir / f"f{frame}.{ext}").resolve())
    (d / f"f{frame}.rec").write_bytes(rec)
    return d


def _what(w: int) -> str:
    pal0, per = vc.PAL0, vc.mm.PAL_ENTRIES
    if w < pal0:
        return f"reg{w * 4:#x}"
    return f"pal{(w - pal0) // per}" if w < vc.BEAM0 else "beam"


def writers(s: Split) -> str:
    """Who writes what: Hp's writes to another plane's palette or to a register,
    G's and frame()'s writes. Each is a way for one pass to see another's work."""
    notes = {f"H{k - 1}->{_what(w)}" for (k, _), d in s.h.items() for w in d if _what(w) != f"pal{k - 1}"}
    notes |= {f"G->{_what(w)}" for d in s.g.values() for w in d}
    notes |= {f"frame()->{_what(w)}" for w in s.frame}
    return " ".join(sorted(notes)) or "-"


def analyse(frames_dir: Path, frame: int, exe: Path) -> str:
    s = split(frames_dir, frame)
    out = []
    for order, rec in (("plane", plane_major(s)), ("line", line_major(s))):
        d = rebuild(frames_dir, frame, rec, order)
        r = video_rtl.replay(exe, d, [frame])
        last = (r.stdout.strip().splitlines() or ["(no output)"])[-1]
        out.append(f"{order}-major: {last.split(': ', 1)[-1]}")
    return f"planes {[k - 1 for k in s.planes]} writers {writers(s)}\n  " + "\n  ".join(out)


if __name__ == "__main__":
    if len(sys.argv) < 3:
        sys.exit("usage: video_order.py <cart tag> <frame> [<frames dir>]")
    tag, f = sys.argv[1], int(sys.argv[2])
    d = Path(sys.argv[3]) if len(sys.argv) > 3 else video_rtl.FPGA / "build" / "vdump" / tag / "frames"
    print(tag, f, analyse(d, f, video_rtl.build_tb()))
