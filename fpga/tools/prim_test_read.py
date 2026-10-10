"""The primitive self-test's results (`make prim-test`, rtl/board/prim_test_top.v) as a PASS/FAIL table.

Load build/prim_test/prim_test_top.bit, then at the U-Boot prompt (the tests run at load, ~3 ms):
    md.l 43c00000 9         ID, CTRL, PASS, DONE, lanes, runs, seed
    md.l 43c00800 168       45 lanes x 8 words
and feed the transcript in:
    uv run python tools/prim_test_read.py dump.txt      (or - for stdin)
    uv run python tools/prim_test_read.py --uboot       (sends the two md.l through tools/uboot.sh)
A restart: `mw.l 43c00004 1`; LOOP (runs accumulate until cleared): `mw.l 43c00004 3`, stop with
`mw.l 43c00004 0`. Exit status 0 only when every lane passed.
"""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

from board_md import parse_md

GP0 = 0x43C00000
LANE_BASE = GP0 + 0x800
HEADER_WORDS = 9
WORDS_PER_LANE = 8
ID = 0x5052494D
# prim_test_lanes.v, in order: (name, what Yosys maps it to)
LANES = [
    ("b36_sdp72", "RAMB36 SDP x72, 512 words (known BAD under openXC7)"),
    ("b36_sdp72_d256", "RAMB36 SDP x72, 256 words"),
    ("b36_sdp72_be8", "RAMB36 SDP x72, 8 byte enables"),
    ("b18_sdp36", "RAMB18 SDP x36, 512 words"),
    ("b18_sdp36_d256", "RAMB18 SDP x36, a 256-word memory"),
    ("b18_sdp36_hi256", "RAMB18 SDP x36, words 256-511 of 512"),
    ("b18_sdp36_a384", "RAMB18 SDP x36, words 384-511 of 512"),
    ("b18_sdp36_be4", "RAMB18 SDP x36, 4 9-bit byte enables"),
    ("b18_sdp32_be4x8", "RAMB18 SDP x36, 32 bits, 4 8-bit byte enables"),
    *[(f"b18_tdp{w}", f"RAMB18 TDP x{w}") for w in (1, 2, 4, 9, 18)],
    ("b18_tdp18_be2", "RAMB18 TDP x18, 2 byte enables"),
    *[(f"b36_tdp{w}", f"RAMB36 TDP x{w}") for w in (1, 2, 4, 9, 18, 36)],
    ("b36_tdp36_be4", "RAMB36 TDP x36, 4 byte enables"),
    ("b36_sp18_wf_be2", "RAMB36 one port x18, WRITE_FIRST, 2 byte enables"),
    ("b36_sp18_rf", "RAMB36 one port x18, READ_FIRST"),
    ("b18_rom9", "RAMB18 x9 read only, contents from the bitstream"),
    ("lut_ram32m", "RAM32M"),
    ("lut_ram64m", "RAM64M"),
    ("srl16e", "SRL16E, clock enable"),
    ("srlc32e", "SRLC32E, clock enable"),
    ("dsp_m", "DSP48E1 a*b, M"),
    ("dsp_abm", "DSP48E1 a*b, A B M"),
    ("dsp_mp", "DSP48E1 a*b, M P"),
    ("dsp_c_m", "DSP48E1 c + a*b, M"),
    ("dsp_macc", "DSP48E1 multiply-accumulate, P"),
    ("dsp_comb", "DSP48E1 a*b, no registers"),
    ("dsp_c_a", "DSP48E1 c + a*b, A"),
    ("dsp_am", "DSP48E1 a*b, A M"),
    ("dsp_bm", "DSP48E1 a*b, B M"),
    ("dsp_c_comb", "DSP48E1 c + a*b, no registers"),
    ("dsp_c_creg", "DSP48E1 c + a*b, C"),
    ("carry4", "CARRY4, a 64-bit add"),
    ("muxf7_f8", "MUXF7 (ABC's LUT7) and MUXF8 (instantiated)"),
    ("b36_tdp18_be2", "RAMB36 TDP x18, 2 byte enables"),
    ("b18_tdp16_be2x8", "RAMB18 TDP x18, 16 bits, 2 8-bit byte enables"),
    ("b36_tdp32_be4x8", "RAMB36 TDP x36, 32 bits, 4 8-bit byte enables"),
]
# (data width, byte width) of the lanes with byte enables: their failures are shown per byte
BYTE_LANES = {
    "b36_sdp72_be8": (72, 9), "b18_sdp36_be4": (36, 9), "b18_sdp32_be4x8": (32, 8), "b18_tdp18_be2": (18, 9),
    "b36_tdp36_be4": (36, 9), "b36_sp18_wf_be2": (18, 9), "b36_tdp18_be2": (18, 9), "b18_tdp16_be2x8": (16, 8),
    "b36_tdp32_be4x8": (32, 8),
}  # fmt: skip


def bad_bytes(name: str, bad: int) -> str:
    """For a byte-enable lane, the byte lanes that ever read wrong ("bytes 1,2"), else ""."""
    if name not in BYTE_LANES or not bad:
        return ""
    width, bw = BYTE_LANES[name]
    lanes = [str(b) for b in range(width // bw) if bad >> (b * bw) & ((1 << bw) - 1)]
    return f" [bytes {','.join(lanes)} of {width // bw}]"


def decode(header: list[int], lanes: list[int]) -> list[dict[str, int | str | bool]]:
    """One row per lane from the header and the lanes' words (prim_test_core.v's map)."""
    if header[0] != ID:
        raise ValueError(f"ID {header[0]:08x}, not {ID:08x}: is the prim-test bitstream loaded?")
    if header[6] != len(LANES):
        raise ValueError(f"the bitstream has {header[6]} lanes, this script knows {len(LANES)}")
    rows = []
    for i, (name, what) in enumerate(LANES):
        w = lanes[i * WORDS_PER_LANE : (i + 1) * WORDS_PER_LANE]
        if w[0] & 0xFF != i:
            raise ValueError(f"lane {i} reads back as lane {w[0] & 0xFF}: a garbled dump")
        bad = w[4] | w[5] << 32 | w[6] << 64
        rows.append({"lane": i, "name": name, "what": what, "done": bool(w[0] >> 31),
                     "pass": bool(w[0] >> 30 & 1), "errors": w[1], "first": w[2], "got": w[3],
                     "bad": bad, "checks": w[7]})  # fmt: skip
    return rows


def table(rows: list[dict[str, int | str | bool]]) -> str:
    lines = [f"{'lane':>4} {'name':18} {'result':7} {'errors':>9} {'checks':>8} first_idx first_got bad bits"]
    for r in rows:
        result = "PASS" if r["pass"] else ("FAIL" if r["done"] else "RUNNING")
        bad = (f"{r['bad']:x}" if r["bad"] else "-") + bad_bytes(str(r["name"]), int(r["bad"]))
        lines.append(f"{r['lane']:4d} {r['name']:18} {result:7} {r['errors']:9d} {r['checks']:8d} "
                     f"{r['first']:08x}  {r['got']:08x}  {bad}   {r['what']}")  # fmt: skip
    failed = [r["name"] for r in rows if not r["pass"]]
    lines.append(
        f"{len(rows) - len(failed)}/{len(rows)} PASS" + (f"; not passing: {', '.join(failed)}" if failed else "")
    )
    return "\n".join(lines)


def read_transcript(text: str) -> tuple[list[int], list[int]]:
    header = parse_md(text, GP0, HEADER_WORDS)
    lanes = parse_md(text, LANE_BASE, len(LANES) * WORDS_PER_LANE)
    if header is None or lanes is None:
        raise ValueError("the transcript lacks a full `md.l 43c00000 9` and `md.l 43c00800 150` (a garbled line?)")
    return header, lanes


def from_uboot() -> str:
    script = Path(__file__).resolve().parent / "uboot.sh"
    cmds = [f"md.l {GP0:x} {HEADER_WORDS:x}", f"md.l {LANE_BASE:x} {len(LANES) * WORDS_PER_LANE:x}"]
    run = subprocess.run(
        [str(script), *cmds], capture_output=True, text=True, check=True, env={**os.environ, "WAIT": "6"}
    )
    return run.stdout


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("transcript", nargs="?", help="a file with the two md.l outputs, - for stdin")
    ap.add_argument("--uboot", action="store_true", help="read the board through tools/uboot.sh")
    args = ap.parse_args(argv)
    if args.uboot:
        text = from_uboot()
    elif args.transcript:
        text = sys.stdin.read() if args.transcript == "-" else Path(args.transcript).read_text()
    else:
        ap.error("give a transcript or --uboot")
    header, lanes = read_transcript(text)
    rows = decode(header, lanes)
    print(f"runs {header[7]}, seed {header[8]:08x}, CTRL {header[1]:x}")
    print(table(rows))
    return 0 if all(r["pass"] for r in rows) else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
