"""What a dumped frame (tools/video_dump.py) exercises in the compositor: which
plane modes, and which per-line effects actually changed something between
lines. A replay that matches proves only what its frames exercise, so
tests/test_rtl_video.py asserts each corpus frame covers what it is there for.

    uv run python tools/video_cover.py build/vdump/<tag>/frames <frame>...
"""

import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "gen"))
import memmap as mm

REG_WORDS = 32
PAL0 = REG_WORDS
BEAM0 = PAL0 + mm.NB_PLANES * mm.PAL_ENTRIES
MODES = {0: "normal", 1: "fullscreen", 2: "scroll", 3: "medium", 4: "overscan"}


def records(path: Path) -> list[tuple[int, int, int, dict[int, int]]]:
    """(kind, pass, raster line, the changed words) in recording order."""
    data, at, out = path.read_bytes(), 0, []
    while at < len(data):
        kind, pas, line, n = struct.unpack_from("<BBHH", data, at)
        at += 6
        delta = {}
        for _ in range(n):
            w, v = struct.unpack_from("<HI", data, at)
            at += 6
            delta[w] = v
        out.append((kind, pas, line, delta))
    return out


def _byte(state: dict[int, int], off: int, size: int) -> int:
    word = state.get(off // 4, 0)
    return (word >> (8 * (off % 4))) & ((1 << (8 * size)) - 1)


def mode_of(state: dict[int, int], plane: int) -> str:
    """video.zig's renderPlane dispatch, including the stride-400 back-compat rule."""
    mode = _byte(state, mm.REG_FB_MODE + plane, 1)
    stride = _byte(state, mm.REG_FB_STRIDE + plane * 2, 2)
    if mode in (1, 2, 3, 4):
        name = MODES[mode]
        return "medium_overscan" if mode == 3 and stride >= mm.RASTER_WIDTH else name
    return "fullscreen" if stride == mm.STRIDE_FULLSCREEN else "normal"


def _effects(delta: dict[int, int], pas: int, state: dict[int, int]) -> set[str]:
    """Effects one handler's writes exercise for the pass consuming them."""
    out = set()
    if pas == 0:
        if _byte(state, mm.REG_BEAM_COUNT, 2):
            out.add("beam")
        if mm.REG_BACKGROUND // 4 in delta:
            out.add("background_per_line")
        return out
    plane = pas - 1
    first, last = PAL0 + plane * mm.PAL_ENTRIES, PAL0 + (plane + 1) * mm.PAL_ENTRIES
    if any(first <= w < last for w in delta):
        out.add("palette_per_line")
    if (mm.REG_HSCROLL + plane * 2) // 4 in delta:
        out.add("hscroll_per_line")
    if mm.REG_RESOLUTION // 4 in delta:
        out.add("resolution_per_line")
    if mm.REG_RES_FLICKER // 4 in delta:
        hpos = _byte(state, mm.REG_FB_HBL_POS + plane * 2, 2)
        on_time = abs(hpos - mm.OVERSCAN_MAGIC_X) <= mm.OVERSCAN_X_TOL
        out.add("flicker_hit" if on_time else "flicker_miss")
    return out


def cover(frames_dir: Path, frame: int) -> set[str]:
    """Modes of the enabled planes and the per-line effects seen in one frame."""
    planes = int((frames_dir / f"f{frame}.meta").read_text().split()[1])
    state: dict[int, int] = {}
    pre: dict[int, int] = {}
    found = set()
    for kind, pas, _line, delta in records(frames_dir / f"f{frame}.rec"):
        state.update(delta)
        if kind == 3 and pas > 0 and (planes >> (pas - 1)) & 1:
            found.add("mode_" + mode_of(state, pas - 1))
        if kind == 1:
            pre = dict(state)
        if kind == 2:
            changed = {w: v for w, v in state.items() if pre.get(w, 0) != v}
            found |= _effects(changed, pas, state)
    if planes.bit_count() > 1:
        found.add("layered")
    return found


if __name__ == "__main__":
    d = Path(sys.argv[1])
    for f in sys.argv[2:]:
        print(f, " ".join(sorted(cover(d, int(f)))))
