"""tools/board_md.py, the `md.l` parser behind tools/board_shot.py, against fake U-Boot
transcripts: a clean dump, and the ways a 921600-baud console without flow control
mangles one (a dropped line, a merged word, a garbled address, an echo)."""

from __future__ import annotations

import struct
import sys
import zlib
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "tools"))
import board_md  # noqa: E402  (tools/ is not a package)
from board_md import parse_md, png_rgb, words_to_bytes  # noqa: E402

START = 0x04C00000


def transcript(words: list[int], start: int = START) -> list[str]:
    """What `md.l <start> <n>` prints: echo, 4 words a line with the ASCII column, prompt."""
    lines = [f"md.l {start:x} {len(words):x}"]
    for i in range(0, len(words), 4):
        chunk = words[i : i + 4]
        lines.append(f"{start + 4 * i:08x}: " + " ".join(f"{w:08x}" for w in chunk) + "    ................")
    return [*lines, "Zynq> "]


WORDS = [0x00FF0000 + i for i in range(10)]  # 2 full lines and a half one


def test_parse_md_returns_every_word_of_a_clean_dump_including_a_short_last_line() -> None:
    assert parse_md("\r\n".join(transcript(WORDS)), START, len(WORDS)) == WORDS


def test_parse_md_refuses_a_dump_with_a_dropped_line() -> None:
    lines = transcript(WORDS)
    del lines[2]
    assert parse_md("\n".join(lines), START, len(WORDS)) is None


def test_parse_md_refuses_a_line_whose_words_ran_together() -> None:
    lines = transcript(WORDS)
    lines[1] = lines[1].replace(" ", "", 2).replace(":", ": ", 1)  # two words merged into 16 digits
    assert parse_md("\n".join(lines), START, len(WORDS)) is None


def test_parse_md_ignores_a_garbled_address_and_then_misses_that_line() -> None:
    lines = transcript(WORDS)
    lines[1] = "04c0x000: " + lines[1].split(": ", 1)[1]
    assert parse_md("\n".join(lines), START, len(WORDS)) is None


def test_parse_md_does_not_take_a_line_from_outside_the_request() -> None:
    # The break: a parser that trusts line order instead of the address would accept a
    # stale line from another request in place of a missing one.
    lines = transcript(WORDS)
    lines[2] = transcript([0xDEAD] * 4, start=START + 0x1000)[1]
    assert parse_md("\n".join(lines), START, len(WORDS)) is None


def test_parse_md_mutant_without_the_address_check_is_caught(monkeypatch: pytest.MonkeyPatch) -> None:
    lines = transcript(WORDS)
    lines[2] = transcript([0xDEAD] * 4, start=START + 0x1000)[1]
    real = board_md.LINE

    class Loose:  # rewrites every address to the one the parser expects next: the order-trusting mutant
        n = 0

        def match(self, s: str) -> object:
            m = real.match(s)
            if not m:
                return None
            fixed = f"{START + 16 * Loose.n:08x}: {m.group(2)}"
            Loose.n += 1
            return real.match(fixed)

    monkeypatch.setattr(board_md, "LINE", Loose())
    assert board_md.parse_md("\n".join(lines), START, len(WORDS)) is not None  # the mutant is fooled


def test_png_rgb_writes_a_valid_png_with_the_picture_bytes_r_g_b(tmp_path: Path) -> None:
    pixels = words_to_bytes([0x000000FF, 0x0000FF00, 0x00FF0000, 0x00FFFFFF])  # {0,B,G,R}: red, green, blue, white
    out = tmp_path / "p.png"
    png_rgb(str(out), 2, 2, pixels)
    data = out.read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n"
    ihdr_len = struct.unpack(">I", data[8:12])[0]
    idat_at = 8 + 12 + ihdr_len
    idat_len = struct.unpack(">I", data[idat_at : idat_at + 4])[0]
    raw = zlib.decompress(data[idat_at + 8 : idat_at + 8 + idat_len])
    assert raw == b"\x00" + b"\xff\x00\x00" + b"\x00\xff\x00" + b"\x00" + b"\x00\x00\xff" + b"\xff\xff\xff"
