"""The board SoC sim's audio (soc/hp_sim.py's tap, rtl/sim/zm_audio_tap.v) against the
native host's (host/audio_soft.c): the same writes, at the same samples, and the same sound.

    uv run python tools/audio_sim_compare.py <native prefix> <uart.txt> <audio_tap.txt> [--mode ym|exact]

- **Writes**: every register write the core applied (tap "W now addr data") against
  every write the machine's players made (native "W ts addr data"), in order, and
  from the first song on each at the same sample counted from that song's start
  (board "ZM SONG ts writes name", native "L ts writes name"). Over the samples both cover.
- **Sound**: the core's samples from the song's start against the machine's
  (tests/tb/audio_stream_cmp.cpp): `exact` for PCM with gains on the register grid,
  `near` (32 LSB) for a player whose f32 gains are off it (the MOD player), `ym` for
  the YM (jt49 vs ym.zig: spectra, partials, envelopes).
Exit 0 when both agree.
"""

from __future__ import annotations

import argparse
import struct
import subprocess
import sys
from pathlib import Path

FPGA = Path(__file__).resolve().parent.parent
CMP_SRC = FPGA / "tests/tb/audio_stream_cmp.cpp"
CMP = FPGA / "build/tests/audio/audio_stream_cmp"

Write = tuple[int, int, int]  # (sample, addr, data)
Song = tuple[int, int]  # (the stamp of its first write, the writes made before it)


def parse_log(text: str, song_tag: str) -> tuple[list[Write], Song | None, list[int]]:
    """W lines, the first song's (stamp, writes before), and S samples (packed L<<16|R)."""
    writes, song, samples = [], None, []
    for line in text.splitlines():
        f = line.split()
        if not f:
            continue
        if f[0] == "W" and len(f) == 4:
            writes.append((int(f[1]), int(f[2], 16), int(f[3], 16)))
        elif f[0] == "S" and len(f) == 3:
            samples.append(int(f[1], 16) << 16 | int(f[2], 16))
        elif line.startswith(song_tag) and song is None and f[len(song_tag.split())].isdigit():
            k = len(song_tag.split())
            song = (int(f[k]), int(f[k + 1]))
    return writes, song, samples


def compare_writes(native: list[Write], ns: Song, board: list[Write], bs: Song, span: int) -> list[str]:
    """Differences, in order. The writes before the song (the boot's: at no common time) by
    value; the song's, by value and sample, counted from its first write."""
    bad = []
    (n0, nk), (b0, bk) = ns, bs
    nb = [w for i, w in enumerate(native) if i < nk or w[0] < n0 + span]
    bb = [w for i, w in enumerate(board) if i < bk or w[0] < b0 + span]
    for i, (a, b) in enumerate(zip(nb, bb, strict=False)):
        rel_a = a[0] - n0 if i >= nk else None
        rel_b = b[0] - b0 if i >= bk else None
        if a[1:] != b[1:] or rel_a != rel_b:
            bad.append(f"write {i}: machine {a[1]:03x}={a[2]:08x} at +{rel_a}, core {b[1]:03x}={b[2]:08x} at +{rel_b}")
    if len(nb) != len(bb):
        bad.append(f"{len(nb)} writes by the machine, {len(bb)} landed in the core over {span} samples")
    return bad


def raw(samples: list[int]) -> bytes:
    return b"".join(struct.pack("<HH", s >> 16, s & 0xFFFF) for s in samples)


def stream_cmp(rtl: list[int], zig: bytes, mode: str, work: Path) -> tuple[bool, str]:
    if not CMP.exists() or CMP.stat().st_mtime < CMP_SRC.stat().st_mtime:
        CMP.parent.mkdir(parents=True, exist_ok=True)
        subprocess.run(["clang++", "-std=c++17", "-O2", str(CMP_SRC), "-o", str(CMP)], check=True)
    (work / "rtl.raw").write_bytes(raw(rtl))
    (work / "zig.raw").write_bytes(zig)
    r = subprocess.run([str(CMP), str(work / "rtl.raw"), str(work / "zig.raw"), mode], capture_output=True, text=True)
    return r.returncode == 0, r.stdout.strip()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("native", type=Path, help="host_audio's ZM_AUDIO_LOG prefix")
    ap.add_argument("uart", type=Path)
    ap.add_argument("tap", type=Path)
    ap.add_argument("--mode", choices=["ym", "exact", "near"], default="ym")
    a = ap.parse_args()
    nw, ns, _ = parse_log(Path(f"{a.native}.w").read_text(), "L ")
    _, bs, _ = parse_log(a.uart.read_text(errors="replace"), "ZM SONG ")
    bw, _, samples = parse_log(a.tap.read_text(), "-")
    if ns is None or bs is None:
        print(f"audio: no song started (machine {ns}, board {bs})")
        return 1
    (n0, _), (b0, _) = ns, bs
    pcm = Path(f"{a.native}.pcm").read_bytes()
    span = min(len(samples) - b0, len(pcm) // 4 - n0)
    bad = compare_writes(nw, ns, bw, bs, span)
    print(f"audio: song at sample {n0} (machine) / {b0} (core); {span} samples compared, "
          f"{sum(w[0] < n0 + span for w in nw)} writes, {len(bad)} differences")
    for line in bad[:10]:
        print("  " + line)
    ok, report = stream_cmp(samples[b0 : b0 + span], pcm[4 * n0 : 4 * (n0 + span)], a.mode, a.tap.parent)
    print(report)
    print("audio: " + ("ok" if ok and not bad else "FAIL"))
    return 0 if ok and not bad else 1


if __name__ == "__main__":
    sys.exit(main())
