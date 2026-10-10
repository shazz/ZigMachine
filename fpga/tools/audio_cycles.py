"""The cost of the music on the cart CPU, from a board SoC sim's UART (cycles/bmain.c
"ZM AF f cart audio" per frame, "ZM HF f total", "ZM SONG ts name").

    uv run python tools/audio_cycles.py build/hcycles/audio/tutorial/uart.txt [--skip 5]

Per frame: `cart` = cart.frame() alone, `audio` = the song bridge and the players
(an SNDH: its 68000 code on Musashi, every PLAY and every timer interrupt of the
samples rendered that frame). Frames before `--skip`, and the frame a song is
loaded in (a one-off: the image staged, depacked, its RAM zeroed), are reported
apart. The budget is 1.67 Mcycles a frame at 100 MHz and 60 fps.
"""

import argparse
import re
import statistics
from pathlib import Path

BUDGET = 100e6 / 60


def pct(xs: list[int], p: float) -> int:
    s = sorted(xs)
    return s[min(len(s) - 1, int(p * (len(s) - 1) + 0.5))]


def summary(name: str, xs: list[int]) -> str:
    if not xs:
        return f"{name}: no frames"
    avg = statistics.fmean(xs)
    return (f"{name}: avg {avg / 1e3:.0f} kc, p95 {pct(xs, 0.95) / 1e3:.0f} kc, max {max(xs) / 1e3:.0f} kc "
            f"({100 * avg / BUDGET:.1f} % of the 1.67 Mc budget on average)")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("uart", type=Path)
    ap.add_argument("--skip", type=int, default=5, help="the first frames (boot, first song) reported apart")
    a = ap.parse_args()
    text = a.uart.read_text(errors="replace")
    af = [(int(f), int(c), int(d)) for f, c, d in re.findall(r"^ZM AF (\d+) (\d+) (\d+)$", text, re.M)]
    lines = text.splitlines()
    loads = set()  # the frames whose audio included a song load: "ZM SONG" printed before their "ZM AF"
    frame = 1
    for line in lines:
        if line.startswith("ZM SONG ") and not line.startswith("ZM SONG MISSING"):
            loads.add(frame)
        m = re.match(r"ZM AF (\d+) ", line)
        if m:
            frame = int(m.group(1)) + 1
    steady = [x for x in af if x[0] > a.skip and x[0] not in loads]
    print(f"{len(af)} frames, song loads in frames {sorted(loads) or 'none'}: "
          + ", ".join(f"frame {f} audio {d / 1e6:.2f} Mc" for f, _, d in af if f in loads))
    print(summary("cart.frame()", [c for _, c, _ in steady]))
    print(summary("audio", [d for _, _, d in steady]))
    print(summary("cart + audio", [c + d for _, c, d in steady]))
    if aud := re.search(r"^ZM AUD .*$", text, re.M):
        print(aud.group())


if __name__ == "__main__":
    main()
