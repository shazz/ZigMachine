"""tools/prim_test_read.py: a U-Boot `md.l` transcript of the prim-test's GP0 block into a PASS/FAIL table."""

import sys
from pathlib import Path

import pytest

FPGA = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(FPGA / "tools"))
import prim_test_read as ptr  # after the path insert

NL = len(ptr.LANES)


def _md(addr: int, words: list[int]) -> str:
    """`md.l` output as U-Boot prints it: 4 words a line, then the ASCII column."""
    lines = []
    for i in range(0, len(words), 4):
        chunk = " ".join(f"{w:08x}" for w in words[i : i + 4])
        lines.append(f"{addr + 4 * i:08x}: {chunk}    ................")
    return "\n".join(lines)


def _dump(failing: int | None = None, ident: int = ptr.ID) -> str:
    """A transcript of both md.l: every lane passed, or `failing` with x72's signature (A half bad)."""
    header = [ident, 0, 0, 0, (1 << 32) - 1, (1 << (NL - 32)) - 1, NL, 1, 0xACE12345]
    lanes = []
    for i in range(NL):
        if i == failing:
            lanes += [0x80000000 | i, 512, 0x00000000, 0x1234, 0xFFFFFFFF, 0xF, 0, 1024]
        else:
            lanes += [0xC0000000 | i, 0, 0xFFFFFFFF, 0, 0, 0, 0, 1024]
    header[2] = sum(1 << i for i in range(min(NL, 32)) if i != failing)
    return "Zynq> md.l 43c00000 9\n" + _md(ptr.GP0, header) + "\nZynq> md.l 43c00800 150\n" + _md(ptr.LANE_BASE, lanes)


def test_an_all_pass_dump_reads_as_every_lane_passing(tmp_path: Path) -> None:
    path = tmp_path / "dump.txt"
    path.write_text(_dump())
    assert ptr.main([str(path)]) == 0


def test_a_failing_lane_shows_its_errors_and_bad_bits() -> None:
    rows = ptr.decode(*ptr.read_transcript(_dump(failing=0)))
    assert (rows[0]["name"], rows[0]["pass"], rows[0]["errors"], rows[0]["bad"]) == (
        "b36_sdp72",
        False,
        512,
        0xFFFFFFFFF,
    )
    assert all(r["pass"] for r in rows[1:])
    assert ptr.table(rows).endswith(f"{NL - 1}/{NL} PASS; not passing: b36_sdp72")


def test_another_bitstream_is_refused() -> None:
    with pytest.raises(ValueError, match="is the prim-test bitstream loaded"):
        ptr.decode(*ptr.read_transcript(_dump(ident=0x5A4D474C)))


def test_a_transcript_with_a_lost_line_is_refused() -> None:
    text = "\n".join(line for line in _dump().splitlines() if not line.startswith("43c00840"))
    with pytest.raises(ValueError, match="lacks a full"):
        ptr.read_transcript(text)


def test_a_byte_enable_lane_names_the_byte_lanes_that_failed() -> None:
    assert ptr.bad_bytes("b18_tdp16_be2x8", 0xFF00) == " [bytes 1 of 2]"
    assert ptr.bad_bytes("b36_sdp72_be8", 0x1FF << 54 | 0x1FF << 9) == " [bytes 1,6 of 8]"


def test_a_lane_without_byte_enables_or_without_errors_shows_no_bytes() -> None:
    assert ptr.bad_bytes("b36_sdp72", 0xFF) == ""
    assert ptr.bad_bytes("b18_tdp16_be2x8", 0) == ""
