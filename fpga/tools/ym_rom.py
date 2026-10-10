"""A YM register dump (YM5!/YM6!, depacked: docs/music/*.ymraw) to a register-
write ROM for the sound-chip players (rtl/board/zm_dump_player.v), and the same
words as a binary for the Zig oracle (tests/audio_ref/audio_ref.zig `rom`).

    uv run python tools/ym_rom.py <in.ymraw> <out.hex> [--bin out.bin] [--frames N] [--loop F]

The ROM is chip-agnostic: 16-bit words, played one 50 Hz frame at a time,
  0rrrrrrr vvvvvvvv   write v to register r
  1nnnnnnn nnnnnnnn   wait n frames (n >= 1)
  0x8000, w           jump to word w (the loop; the last two words)
For the YM, a frame writes registers 0..12 when they change and R13 unless it
is 0xFF: libs/zig/players/ym_player.zig writes all fourteen every frame, but
rewriting a register with its value changes nothing on the chip except R13,
where it retriggers the envelope, and 0xFF is the format's "no write" (ym.zig
ignores it). The loop's first frame writes all thirteen, since it can follow
any frame. tests/test_rtl_audio.py checks that the Zig machine plays this ROM
and the .ymraw identically.
"""

import argparse
import struct
import sys
from pathlib import Path


def parse_ym(data: bytes) -> tuple[list[list[int]], int, int]:
    """(frames of 14 registers, loop frame, frame rate) from a YM5!/YM6! file."""
    if data[:4] not in (b"YM5!", b"YM6!"):
        raise ValueError("not a depacked YM5!/YM6! file")
    nb, attr, ndrums, _clock, rate, loop, fut = struct.unpack(">IIHIHIH", data[12:34])
    off = 34 + fut
    for _ in range(ndrums):
        off += 4 + struct.unpack(">I", data[off : off + 4])[0]
    for _ in range(3):
        off = data.index(0, off) + 1
    regs = data[off : off + nb * 16]
    if len(regs) != nb * 16:
        raise ValueError("truncated register data")
    at = (lambda f, r: regs[r * nb + f]) if attr & 1 else (lambda f, r: regs[f * 16 + r])
    return [[at(f, r) for r in range(14)] for f in range(nb)], loop if loop < nb else 0, rate or 50


def frame_words(regs: list[int], prev: list[int] | None) -> list[int]:
    words = [r << 8 | v for r, v in enumerate(regs[:13]) if prev is None or prev[r] != v]
    if regs[13] != 0xFF:
        words.append(13 << 8 | regs[13])
    return words


def build(frames: list[list[int]], loop: int) -> list[int]:
    """The ROM: each frame's writes then a wait; frames that write nothing
    lengthen the wait before them."""
    words: list[int] = []
    loop_word = 0
    prev: list[int] = [0] * 14
    for f, regs in enumerate(frames):
        if f == loop:
            loop_word = len(words)
        writes = frame_words(regs, None if f == loop else prev)
        prev = regs
        if not writes and words and words[-1] & 0x8000 and words[-1] < 0xFFFF:
            words[-1] += 1
        else:
            words += [*writes, 0x8001]
    return [*words, 0x8000, loop_word]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("ym", type=Path)
    ap.add_argument("hex", type=Path)
    ap.add_argument("--bin", type=Path)
    ap.add_argument("--frames", type=int, help="an excerpt: the first N frames, looped")
    ap.add_argument("--loop", type=int, help="the frame the loop goes back to (default: the file's)")
    a = ap.parse_args()
    frames, loop, rate = parse_ym(a.ym.read_bytes())
    if rate != 50:
        raise SystemExit(f"{a.ym}: {rate} Hz frames; the player is 50 Hz")
    if a.frames:
        frames, loop = frames[: a.frames], (loop if loop < a.frames else 0)
    if a.loop is not None:
        if not 0 <= a.loop < len(frames):
            raise SystemExit(f"--loop {a.loop}: outside the {len(frames)} frames")
        loop = a.loop
    words = build(frames, loop)
    if len(words) > 0x10000:
        raise SystemExit(f"{len(words)} words: more than the 16-bit jump reaches")
    a.hex.write_text("".join(f"{w:04x}\n" for w in words))
    if a.bin:
        a.bin.write_bytes(struct.pack(f"<{len(words)}H", *words))
    print(f"{a.ym.name}: {len(frames)} frames ({len(frames) / 50:.1f} s), loop at frame {loop}, {len(words)} words")
    return 0


if __name__ == "__main__":
    sys.exit(main())
