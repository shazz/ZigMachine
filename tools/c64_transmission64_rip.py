#!/usr/bin/env python3
"""c64_transmission64_rip.py: rip Padua's Transmission64 invitation (C64, 2021) for
apps/zig/scenes/c64_transmission64.

Boots the original PRG in VICE (tools/c64/vicemon.py). The frame clock starts at part 1's
first IRQ ($2B7B, line 248): frame 1 holds it. (The $2800 entry first uploads code to drive 8
over the serial bus, which takes 33 or 34 frames depending on the drive: numbering from $2800
would differ run to run.) Dumps RAM where each part starts, statically parses the generated
code, and measures, frame by frame, where the routines that race the beam start (they follow
the SID player's call, whose CPU time varies with the tune).

Writes apps/zig/assets/screens/c64_transmission64/ (layouts in scenes/c64_transmission64/data.zig):
  part1.bin   boot screen + colours as part 1 saved them ($7400/$7800), the charset ($2000),
              the 242 feed codes ($7C00), the 24 rings' cells (parsed from $2C80's code),
              the frame-by-frame start of $2C80, the VIC registers and $DD00 at frame 1
  wipe.bin    the transitions' tables: IRQ lines ($0B00), their bit 8 ($0B80), delays ($0A0D)
  transmission_64.sid   the tune, HVSC /MUSICIANS/T/Toggle/Transmission_64.sid, byte-identical
              to $0C00-$2000 of the program (checked here)

  python3 tools/c64_transmission64_rip.py [prg] [hvsc.sid]
"""
import hashlib
import os
import pickle
import re
import struct
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tools", "c64"))
sys.path.insert(0, os.path.join(ROOT, "tools"))
from vicemon import Vice  # noqa: E402

import c64_transmission64_parts as parts  # noqa: E402

OUT = os.path.join(ROOT, "apps/zig/assets/screens/c64_transmission64")
PRG = os.path.join(ROOT, "prototypes/transmission64_re/orig/transmission64-2021.prg")
SID = os.path.join(ROOT, "prototypes/transmission64_re/sid/hvsc.sid")
PRG_MD5 = "6885aa9f4f78111565cb2eff9ad1d201"  # CSDb release 200255's transmission64-2021.prg
SID_MD5 = "53b214e31189106ecfb556fe05e15935"
FIRST_IRQ = 0x2B7B
PART1_FRAMES = 726  # 242 feed codes x 3 frames


def regs(v: Vice) -> tuple[str, int, int, int]:
    r = v.cmd("r").strip().splitlines()[-2].split()
    return r[0][2:], int(r[-3]), int(r[-2]), int(r[-1])


def dump(v: Vice, tmp: str, tag: str) -> dict[str, bytes]:
    out = {}
    for name, bank, rng in (("ram", "ram", "0000 ffff"), ("io", "io", "d000 dfff")):
        path = os.path.join(tmp, f"{tag}.{name}")
        v.cmd(f"bank {bank}")
        v.cmd(f'bsave "{path}" 0 {rng}')
        out[name] = open(path, "rb").read()
    v.cmd("bank cpu")
    return out


def stop_at(v: Vice, addr: str) -> None:
    bp = re.search(r"BREAK: (\d+)", v.cmd(f"break {addr}")).group(1)
    v.cmd("x")
    v.cmd(f"delete {bp}")


def run(prg: str) -> dict:
    """One VICE run: RAM/IO at frame 1's IRQ; part 1's $2C80 starts; part 2's dumps and
    timeline (parts.P2_PCS hits as (frame, pc, line, cycle, $0C1E, $0C22))."""
    with tempfile.TemporaryDirectory() as tmp:
        v = Vice(prg, 0x2800)
        v.cmd("delete")  # the -initbreak checkpoint
        entry = dump(v, tmp, "entry")
        stop_at(v, f"{FIRST_IRQ:04x}")
        first = dump(v, tmp, "first")
        first["entry"] = entry["ram"]
        _, l0, c0, k0 = regs(v)
        base = k0 - ((l0 - 288) % 312) * 63 - c0  # clock of line 288 before frame 1
        bp = re.search(r"BREAK: (\d+)", v.cmd("break 2c80")).group(1)
        hits = []
        for _ in range(PART1_FRAMES):
            v.cmd("x")
            pc, line, cyc, clk = regs(v)
            hits.append(((clk - base) // 19656 + 1, pc, line, cyc))
        v.cmd(f"delete {bp}")
        out = {"first": first, "p1_hits": hits}
        out.update(run_part2(v, tmp, base))
        stop_at(v, "085a")  # the main loop after decrunching part 3
        stop_at(v, "3808")
        out["p3"] = dump(v, tmp, "p3")
        out["p3_gen"] = run_part3_gen(v, base)
        v.close()
    return out


def run_part3_gen(v: Vice, base: int) -> list[tuple[int, int, int]]:
    """At each shape change (every 969 frames from 3628), $40AA's entry: the generator's write
    pointer ($18/$19) and Y (bytes of the block in progress)."""
    out = []
    for j in range(parts.GEN_CHANGES):
        f = parts.FIRST_CHANGE + parts.CYCLE * j
        target = base + (f - 1) * 19656 + (24 + 200) * 63
        clk = 0
        while clk < target:
            stop_at(v, "40aa")
            _, line, cyc, clk = regs(v)
        m = v.mem(0x18, 0x19)
        y = int(v.cmd("r").strip().splitlines()[-2].split()[3], 16)
        out.append(((clk - base) // 19656 + 1, m[0] | m[1] << 8, y))
    return out


def run_part2(v: Vice, tmp: str, base: int) -> dict:
    stop_at(v, "082a")  # the main loop after decrunching part 2 (its code overlays part 1's)
    stop_at(v, "4000")
    for a in parts.P2_PCS:
        v.cmd(f"break {a}")
    hits, done = [], None
    while True:
        v.cmd("x")
        pc, line, cyc, clk = regs(v)
        mus = (0, 0)
        if pc == "41fd":
            m = v.mem(0x0C1E, 0x0C22)
            mus = (m[0], m[4])
        if pc == "4062":
            done = dump(v, tmp, "p2")
        hits.append(((clk - base) // 19656 + 1, pc, line, cyc, clk - base) + mus)
        if pc == "0832":
            break
    v.cmd("delete")
    return {"p2_hits": hits, "p2": done}  # clocks relative to line 288 before frame 1


def rings(m: bytes) -> list[list[int]]:
    """Part 1's $2C80: per ring ($27 first) the screen offsets its draw path writes, checked
    against its restore path (same cells, same order)."""
    a = 0x2C80
    assert m[a:a + 2] == b"\xA0\x0E"
    a += 2
    out = []
    while m[a] == 0xA6:
        assert m[a + 2:a + 5] == b"\xD0\x03\x4C"
        restore = m[a + 5] | m[a + 6] << 8
        d, cells = a + 7, []
        while m[d] == 0x8E:
            sx = m[d + 1] | m[d + 2] << 8
            assert m[d + 3] == 0x8C and (m[d + 4] | m[d + 5] << 8) == sx + 0xD400
            cells.append(sx - 0x400)
            d += 6
        assert m[d] == 0x4C and d + 3 == restore
        r, back = restore, []
        while m[r] == 0xAD:
            dst = m[r + 4] | m[r + 5] << 8
            assert (m[r + 1] | m[r + 2] << 8) == dst + 0x7000 and (m[r + 10] | m[r + 11] << 8) == dst + 0xD400
            back.append(dst - 0x400)
            r += 12
        assert back == cells and r == (m[d + 1] | m[d + 2] << 8)
        out.append(cells)
        a = r
    assert m[a] == 0x60 and len(out) == 24 and sum(len(c) for c in out) == 1000
    return out


def part1(first: dict[str, bytes], hits: list[tuple[int, str, int, int]]) -> bytes:
    m, io = first["ram"], first["io"]
    starts = [line * 63 + cyc + 1 - 248 * 63 for f, pc, line, cyc in hits]  # +1: the fetch cycle
    assert [h[0] for h in hits] == list(range(1, PART1_FRAMES + 1)), "one $2C80 a frame"
    assert m[0x7400:0x77E8] == m[0x0400:0x07E8], "the saved screen is the screen"
    rs = rings(m)
    blob = bytearray()
    blob += m[0x7400:0x77E8]  # screen 1000
    blob += bytes(c & 15 for c in m[0x7800:0x7BE8])  # colours 1000
    blob += m[0x2000:0x2800]  # charset 2048
    blob += m[0x7C00:0x7CF2]  # feed 242
    blob += struct.pack("<24H", *(len(c) for c in rs))
    for c in rs:
        blob += struct.pack(f"<{len(c)}H", *c)
    blob += struct.pack(f"<{PART1_FRAMES}H", *starts)
    blob += io[0:0x2F] + io[0xD00:0xD01]  # VIC registers, $DD00
    return bytes(blob)


def wipe(m: bytes) -> bytes:
    return m[0x0B00:0x0B80] + m[0x0B80:0x0C00] + m[0x0A0D:0x0A8D]


def main() -> None:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    prg = args[0] if args else PRG
    sid = args[1] if len(args) > 1 else SID
    assert hashlib.md5(open(prg, "rb").read()).hexdigest() == PRG_MD5, "not CSDb 200255's PRG"
    song = open(sid, "rb").read()
    assert hashlib.md5(song).hexdigest() == SID_MD5
    # the VICE run takes minutes: kept (our own file) so a layout change needs no new run
    cache = os.path.join(ROOT, "prototypes/transmission64_re/scratch/rip_run.pickle")
    if "--fresh" not in sys.argv and os.path.exists(cache):
        r = pickle.load(open(cache, "rb"))  # noqa: S301 -- written by this script, below
    else:
        r = run(prg)
        pickle.dump(r, open(cache, "wb"))
    first = r["first"]
    body = song[0x7C + 2:]
    assert first["entry"][0x0C00:0x0C00 + len(body)] == body, "the tune is HVSC's, byte for byte"
    os.makedirs(OUT, exist_ok=True)
    for name, data in (("part1.bin", part1(first, r["p1_hits"])), ("wipe.bin", wipe(first["ram"])),
                       ("part2.bin", parts.part2(r["p2"], r["p2_hits"])),
                       ("part3.bin", parts.part3(r["p3"]["ram"], r["p3_gen"])),
                       ("transmission_64.sid", song)):
        open(os.path.join(OUT, name), "wb").write(data)
        print(name, len(data))


if __name__ == "__main__":
    main()
