"""MP3 output path probe (fpga/review/MP3_BARD_STUDY.md, option b): can two Paula channels a side, a
high byte at VOL 256 and a low byte at VOL v, carry a 16-bit sample through CHORUS to its 16-bit out?

Plays one stimulus on the RTL (CXXRTL core bench) and on the Zig engine (the browser's machine-audio),
then compares the 16-bit out with x and with floor(x / 2).
    uv run python tests/hilo_probe.py     (from fpga/, after tests/test_rtl_audio.py has built once)
"""

import random
import struct
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import test_rtl_audio as t  # noqa: E402  the bench builder

N = 6000
D = t.BUILD / "hilo"


def split(x: int, lo_vol: int) -> tuple[int, int]:
    """hi, lo bytes with 256 hi + lo = x (lo VOL 1) or 128 hi + lo = x >> 1 (lo VOL 2)."""
    y, w = (x, 256) if lo_vol == 1 else (x >> 1, 128)
    hi = max(-128, min(127, (y + w // 2) // w))
    return hi, y - w * hi


def stimulus(lo_vol: int) -> tuple[list[int], list[int]]:
    rnd = random.Random(7)
    xl = [-32768, 32767, -1, 0, 1, 255, 256, -257] + [rnd.randrange(-32768, 32768) for _ in range(N - 8)]
    xr = [rnd.randrange(-20000, 20000) for _ in range(N)]
    planes = [[], [], [], []]
    for a, b in zip(xl, xr, strict=True):
        for k, v in ((0, a), (2, b)):
            hi, lo = split(v, lo_vol)
            if not -128 <= lo <= 127:
                hi, lo = hi, max(-128, min(127, lo))  # out of reach: clipped, the compare shows it
            planes[k].append(hi & 255)
            planes[k + 1].append(lo & 255)
    D.mkdir(parents=True, exist_ok=True)
    (D / "hilo.bin").write_bytes(bytes(sum(planes, [])))
    lines = ["pcm hilo/hilo.bin", "run 2"]
    for c, (vol, pan) in enumerate(((256, -128), (lo_vol, -128), (256, 128), (lo_vol, 128))):
        lines += [f"vol {c} {vol}", f"pan {c} {pan}"]
    lines += [f"trig {c} {c * N} {N} 0 0 {(-128, -128, 128, 128)[c]}" for c in range(4)]
    lines += [f"step {c} 65536" for c in range(4)] + [f"run {N + 4}"]
    (D / "hilo.txt").write_text("\n".join(lines) + "\n")
    return xl, xr


def stereo(path: Path) -> tuple[list[int], list[int]]:
    s = struct.unpack(f"<{path.stat().st_size // 2}h", path.read_bytes())
    return list(s[0::2]), list(s[1::2])


def report(name: str, out: tuple[list[int], list[int]], xl: list[int], xr: list[int]) -> None:
    ol, orr = out
    start = next(i for i, v in enumerate(ol) if v)  # the channels' first sample
    got = list(zip(ol[start : start + N], orr[start : start + N], strict=True))
    for want, label in ((lambda x: x, "x"), (lambda x: x >> 1, "x>>1")):
        bad = [i for i, (g, a, b) in enumerate(zip(got, xl, xr, strict=True)) if g != (want(a), want(b))]
        print(f"  {name}: out == {label}: {N - len(bad)}/{N} samples" + (f", first miss #{bad[0]}: out {got[bad[0]]} x {(xl[bad[0]], xr[bad[0]])}" if bad else ""))


def main() -> int:
    exe = t.build_bench("core")
    for lo_vol in (1, 2):
        xl, xr = stimulus(lo_vol)
        print(f"lo byte at VOL {lo_vol}:")
        assert t._run([str(exe), "hilo/hilo.txt", "/dev/null", "dump", "hilo/rtl.raw"]).returncode in (0, 1)
        assert t._run([str(t.BUILD / "audio_ref"), "hilo/hilo.txt", "hilo/zig.raw"]).returncode == 0
        report("RTL ", stereo(D / "rtl.raw"), xl, xr)
        report("Zig ", stereo(D / "zig.raw"), xl, xr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
