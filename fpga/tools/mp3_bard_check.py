"""The BARD MP3 study's summary: BARD's per-frame lines (snd-cbench uart) against the host twin.

    python3 tools/mp3_bard_check.py <uart.txt> <host build dir>

Fails unless every frame BARD decoded has the host's PCM hash (bit-exact); prints, per stream, the warm
frames' mean cycles (frame 0 dropped), the load on BARD at the stream's rate, and the soft divides.
"""

import sys
from pathlib import Path


def bard_lines(uart: Path) -> dict[str, list[list[str]]]:
    out: dict[str, list[list[str]]] = {}
    for line in uart.read_text(errors="replace").splitlines():
        f = line.split()
        if f[:1] == ["MP3"]:
            out.setdefault(f[2], []).append(f)
    return out


def host_hashes(path: Path) -> list[str]:
    return [line.split()[-1] for line in path.read_text().splitlines()]


def main() -> int:
    uart, host = Path(sys.argv[1]), Path(sys.argv[2])
    bad = 0
    for stream, frames in bard_lines(uart).items():
        ref = host_hashes(host / f"{stream}.txt")
        for f in frames:
            if f[-1] != ref[int(f[3])]:
                print(f"{stream} frame {f[3]}: BARD {f[-1]} host {ref[int(f[3])]}")
                bad += 1
        warm = frames[1:] or frames
        cyc = sum(int(f[5]) for f in warm) / len(warm)
        load = sum(float(f[11]) for f in warm) / len(warm)
        peak = max(float(f[11]) for f in frames)
        print(f"{f[1]} {stream}: {cyc / 1e6:.3f} Mc/MP3 frame, {load:.1f} % of BARD (peak {peak:.1f} %), div {warm[-1][14]}/frame")
    print("bit-exact with the host" if not bad else f"{bad} frames differ")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
