"""c64_transmission64_parts.py: the layouts tools/c64_transmission64_rip.py writes for parts 2
and 3 (scenes/c64_transmission64/data.zig reads them). Pure functions over VICE's dumps and
breakpoint hits; no emulator here.

A hit is (frame, pc, line, cycle, clock, $0C1E, $0C22): clock counts from line 288 before
frame 1, so frame N's line 0 is at (N - 1) * 19656 + 24 * 63."""
import struct

FRAME = 19656
# part 2: overlay done, IRQ entry, its $4700 call, its RTI, the colour cycles' copy loops
# (ldx #0 before them) and entries, the return to the main loop
P2_PCS = ["4062", "4175", "41cc", "41fd", "421b", "4251", "42ad", "42e3", "0832"]
# the generated radio-ring routine $4700: LDA/ORA/AND #/LDX abs and STA/STX abs only
OPLEN = {0xAD: 3, 0x0D: 3, 0x29: 2, 0xAE: 3, 0x8D: 3, 0x8E: 3}


def line0(n: int) -> int:
    return (n - 1) * FRAME + 24 * 63


def program_4700(m: bytes) -> bytes:
    """$4700..RTS as (opcode, operand lo, operand hi) triples, the count first."""
    a, ops = 0x4700, []
    while m[a] != 0x60:
        n = OPLEN[m[a]]  # KeyError = an opcode the port does not know
        ops.append(bytes((m[a], m[a + 1], m[a + 2] if n == 3 else 0)))
        a += n
    return struct.pack("<H", len(ops)) + b"".join(ops)


def irq_table(hits: list) -> tuple[int, list[tuple[int, int, int, int]]]:
    """Per part-2 frame from the first IRQ: (entry, $4700 start, RTI end, music flags), times
    in cycles from the frame's line 0; a frame with no IRQ (the drive command's SEI) is
    (0xFFFF, 0, 0, 0)."""
    per, cur = {}, None
    for f, pc, line, cyc, clk, c1e, c22 in hits:
        if pc == "4175":
            cur = f
            per[f] = [clk - line0(f) + 1, 0, 0, 0]  # +1: VICE stops one cycle before the fetch
        elif pc == "41cc" and cur is not None:
            per[cur][1] = clk - line0(cur) + 7  # past its JSR
        elif pc == "41fd" and cur is not None:
            per[cur][2] = clk - line0(cur) + 7  # past the RTI
            per[cur][3] = (1 if c1e in (0xB2, 0xA0) else 0) | (2 if c22 == 0x11 else 0)
    first, last = min(per), max(per)
    rows = [tuple(per.get(f, (0xFFFF, 0, 0, 0))) for f in range(first, last + 1)]
    return first, rows


def cycles(hits: list) -> list[tuple[int, int, int]]:
    """The colour cycles: (frame of the copy loop's start, its time in that frame, variant)."""
    out = []
    for f, pc, line, cyc, clk, *_ in hits:
        if pc in ("4251", "42e3"):
            out.append((f, clk - line0(f) + 1, 0 if pc == "4251" else 1))
    return out


def events(hits: list) -> bytes:
    """(frame, time) of the overlay copy's end ($4062: the sprite is set up) and of the return
    to the main loop ($0832: part 2 is over)."""
    ev = {pc: (f, clk - line0(f) + 1) for f, pc, line, cyc, clk, *_ in hits if pc in ("4062", "0832")}
    return struct.pack("<4H", *ev["4062"], *ev["0832"])


def part2(d: dict, hits: list) -> bytes:
    m, io = d["ram"], d["io"]
    first, rows = irq_table(hits)
    cyc = cycles(hits)
    assert all(b == 0x04 for b in m[0x4500:0x4519]) and all(b == 0x40 for b in m[0x4600:0x4619])
    sections = [
        m[0x2000:0x3F40], m[0x0400:0x07E8], bytes(c & 15 for c in io[0x800:0xBE8]),
        m[0x7000:0x7400], m[0x7900:0x7A00],
        m[0x4500:0x4519] + m[0x4600:0x4619] + m[0x43F2:0x43FA],
        program_4700(m),
        struct.pack("<HH", first, len(rows)) + b"".join(struct.pack("<HHHB", *r) for r in rows),
        struct.pack("<H", len(cyc)) + b"".join(struct.pack("<HHB", *c) for c in cyc),
        io[0:0x2F] + io[0xD00:0xD01],
        events(hits),
    ]
    head = 4 * len(sections)
    offs, pos = [], head
    for s in sections:
        offs.append(pos)
        pos += len(s)
    return struct.pack(f"<{len(sections)}I", *offs) + b"".join(sections)
