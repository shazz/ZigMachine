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


VOLUMES = (0x020, 0x024, 0x028)  # YM regs 8-10 (host/audio_queue.h zma_dedup_keep)
CTRL = 0x040


def board_queue(native: list[Write], song: Song) -> tuple[list[Write], Song]:
    """The machine's writes as the board queues them (host/audio_queue.h): a YM volume write of the
    value last queued for its register is dropped, and the chip reset forgets them. The song's
    write count moves with what was dropped before it."""
    last: dict[int, int] = {}
    kept, before = [], 0
    for i, w in enumerate(native):
        if w[1] == CTRL:
            last.clear()
        elif w[1] in VOLUMES:
            if last.get(w[1]) == w[2]:
                continue
            last[w[1]] = w[2]
        kept.append(w)
        before += i < song[1]
    return kept, (song[0], before)


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


Start = tuple[int, int, str]  # (stamp, writes before, name): one song request


def song_starts(text: str, tag: str) -> list[Start]:
    """Every song started, in order (each start is logged twice, as the bridge and the player see it)."""
    out: list[Start] = []
    for line in text.splitlines():
        f = line[len(tag) :].split() if line.startswith(tag) else []
        if len(f) == 3 and f[0].isdigit() and f[1].isdigit() and (not out or out[-1] != (int(f[0]), int(f[1]), f[2])):
            out.append((int(f[0]), int(f[1]), f[2]))
    return out


def song_segments(native: list[Write], ns: list[Start], board: list[Write], bs: list[Start], ends: tuple[int, int]):
    """Per song: (name, the machine's writes as the board queues them, its start, the core's, its start, span).
    The two sides' songs start at different frames when the cart runs below 60 fps in the sim, so each
    song is timed from its own start, over the samples both sides played it."""
    cut = [board_queue(native, (s[0], s[1]))[1][1] for s in ns]
    queued = board_queue(native, (0, 0))[0]
    for i, (n, b) in enumerate(zip(ns, bs, strict=True)):
        last = i + 1 == len(ns)
        span = min((ends[0] if last else ns[i + 1][0]) - n[0], (ends[1] if last else bs[i + 1][0]) - b[0])
        yield (n[2], queued[cut[i] : None if last else cut[i + 1]], (n[0], 0),
               board[b[1] : None if last else bs[i + 1][1]], (b[0], 0), span)


def compare_songs(a: argparse.Namespace, native_log: str, uart: str, samples: list[int], pcm: bytes) -> int:
    """--songs: every song the cart started, its writes and its sound, each from its own start."""
    nw, _, _ = parse_log(native_log, "L ")
    bw, _, _ = parse_log(a.tap.read_text(), "-")
    ns, bs = song_starts(native_log, "L "), song_starts(uart, "ZM SONG ")
    if not ns or [s[2] for s in ns] != [s[2] for s in bs]:
        print(f"audio: the songs differ: machine {[s[2] for s in ns]}, board {[s[2] for s in bs]}")
        return 1
    fail = 0
    for i, (name, nseg, n0, bseg, b0, span) in enumerate(song_segments(nw, ns, bw, bs, (len(pcm) // 4, len(samples)))):
        bad = compare_writes(nseg, n0, bseg, b0, span)
        # The sound only for the first: a later song starts on the chip state (tone phases, the POKEY's
        # polynomial counters) the previous one left after playing for a different time on each side.
        ok, report = (True, "sound: not compared after a switch") if i else stream_cmp(
            samples[b0[0] : b0[0] + span], pcm[4 * n0[0] : 4 * (n0[0] + span)], a.mode, a.tap.parent)
        print(f"audio: {name} at {n0[0]} / {b0[0]}: {span} samples, "
              f"{sum(w[0] < n0[0] + span for w in nseg)} writes, {len(bad)} differences; {report}")
        for line in bad[:5]:
            print("  " + line)
        fail |= bool(bad) or not ok
    print("audio: " + ("FAIL" if fail else "ok"))
    return int(fail)


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
    ap.add_argument("--no-dedup", action="store_true", help="a board from before the queue dropped repeated volumes")
    ap.add_argument("--songs", action="store_true", help="every song the cart started, not only the first")
    a = ap.parse_args()
    if a.songs:
        uart, (_, _, samples) = a.uart.read_text(errors="replace"), parse_log(a.tap.read_text(), "-")
        return compare_songs(a, Path(f"{a.native}.w").read_text(), uart, samples, Path(f"{a.native}.pcm").read_bytes())
    nw, ns, _ = parse_log(Path(f"{a.native}.w").read_text(), "L ")
    if ns is not None and not a.no_dedup:
        nw, ns = board_queue(nw, ns)
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
